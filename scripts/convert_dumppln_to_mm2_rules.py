#!/usr/bin/env python3
"""Convert a ConceptNet PLN dump into mm2-chainer ruleN rules."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import TextIO


Expr = str | list["Expr"]


def skip_ws(text: str, index: int) -> int:
    while index < len(text) and text[index].isspace():
        index += 1
    return index


def tokenize(text: str) -> list[str]:
    tokens: list[str] = []
    index = 0
    while index < len(text):
        char = text[index]
        if char.isspace():
            index += 1
        elif char in "()":
            tokens.append(char)
            index += 1
        else:
            end = index
            while end < len(text) and not text[end].isspace() and text[end] not in "()":
                end += 1
            tokens.append(text[index:end])
            index = end
    return tokens


def read_expr(tokens: list[str], index: int = 0) -> tuple[Expr, int]:
    if index >= len(tokens):
        raise ValueError("unexpected end of expression")

    token = tokens[index]
    if token != "(":
        return token, index + 1

    index += 1
    result: list[Expr] = []
    while index < len(tokens) and tokens[index] != ")":
        child, index = read_expr(tokens, index)
        result.append(child)
    if index >= len(tokens):
        raise ValueError("unclosed list expression")
    return result, index + 1


def parse_line(text: str) -> Expr:
    tokens = tokenize(text)
    expr, index = read_expr(tokens)
    if index != len(tokens):
        raise ValueError("trailing tokens after expression")
    return expr


def render_expr(expr: Expr) -> str:
    if isinstance(expr, list):
        return "(" + " ".join(render_expr(item) for item in expr) + ")"
    return expr


def render_pcons(items: list[Expr]) -> str:
    result = "pnil"
    for item in reversed(items):
        result = f"(pcons {render_expr(item)} {result})"
    return result


def require_list(expr: Expr, context: str) -> list[Expr]:
    if not isinstance(expr, list):
        raise ValueError(f"{context} must be a list")
    return expr


def convert_statement(expr: Expr, line_no: int) -> str:
    stmt = require_list(expr, f"line {line_no}")
    if len(stmt) != 4 or stmt[0] != ":":
        raise ValueError(f"line {line_no}: expected (: proof implication tv)")

    _, proof_id, implication_expr, tv_expr = stmt
    implication = require_list(implication_expr, f"line {line_no} implication")
    if len(implication) != 3 or implication[0] != "Implication":
        raise ValueError(f"line {line_no}: expected Implication statement")

    premises_expr = require_list(implication[1], f"line {line_no} premises")
    conclusions_expr = require_list(implication[2], f"line {line_no} conclusions")
    if not premises_expr or premises_expr[0] != "Premises":
        raise ValueError(f"line {line_no}: expected Premises list")
    if not conclusions_expr or conclusions_expr[0] != "Conclusions":
        raise ValueError(f"line {line_no}: expected Conclusions list")

    premises = premises_expr[1:]
    conclusions = conclusions_expr[1:]
    if len(conclusions) != 1:
        raise ValueError(f"line {line_no}: expected exactly one conclusion")

    tv = require_list(tv_expr, f"line {line_no} tv")
    if len(tv) != 3 or tv[0] != "CTV":
        raise ValueError(f"line {line_no}: expected CTV")
    pos = require_list(tv[1], f"line {line_no} positive STV")
    neg = require_list(tv[2], f"line {line_no} negative STV")
    if len(pos) != 3 or pos[0] != "STV":
        raise ValueError(f"line {line_no}: expected positive STV")
    if len(neg) != 3 or neg[0] != "STV":
        raise ValueError(f"line {line_no}: expected negative STV")

    return (
        f"(ruleN {render_expr(conclusions[0])} {render_expr(proof_id)} "
        f"(ctv ({render_expr(pos[1])} {render_expr(pos[2])}) "
        f"({render_expr(neg[1])} {render_expr(neg[2])})) "
        f"{render_pcons(premises)})"
    )


def convert(input_file: TextIO, output_file: TextIO) -> int:
    count = 0
    for line_no, raw_line in enumerate(input_file, start=1):
        line = raw_line.strip()
        if not line:
            continue
        output_file.write(convert_statement(parse_line(line), line_no))
        output_file.write("\n")
        count += 1
    return count


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Convert cnet dumppln.txt statements into mm2 ruleN rules."
    )
    parser.add_argument("input", type=Path, help="Path to dumppln.txt")
    parser.add_argument("output", type=Path, help="Output .mm2 rules path")
    args = parser.parse_args()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.input.open(encoding="utf-8") as input_file:
        with args.output.open("w", encoding="utf-8") as output_file:
            count = convert(input_file, output_file)
    print(f"converted {count} rules to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
