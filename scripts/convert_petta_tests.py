#!/usr/bin/env python3
"""Convert PeTTaChainer metta tests into mm2-chainer FFI-harness tests.

Mechanical rewrite:
  !(import! &self petta_chainer)        -> harness import + !(mm2-init)
  !(import! &self logic_configs/...)    -> absolute PeTTaChainer import
  (compileadd kb stmt)                  -> (mm2-compileadd kb stmt)
  !(test (query N kb pat) expected)     -> !(mm2-test-query N kb pat <list>)
  !(test (collapse (query ...)) exp)    -> !(mm2-test-query ... exp)

Expected results are normalized to a list: () stays, a single (: ...) is
wrapped, an existing list is kept. Constructs the harness doesn't know
(set-base-rate, fc, chainer internals, ...) are passed through unchanged so
they surface as unreduced terms in the run report — that's the gap list.

Files whose tests are entirely out of scope (forward chainer, distribution /
particle values) are skipped.
"""

import re
import sys
from pathlib import Path

SRC_DIR = Path("/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/pettachainer/metta/tests")
PETTA_METTA_DIR = SRC_DIR.parent
DST_DIR = Path(__file__).resolve().parent.parent / "tests" / "harness" / "generated"
HARNESS = "/nexus/Dev/OpenCog/NL2PLN_Project/mm2-chainer/compiler/mm2_chainer"

SKIP_FILES = {
    "test.metta",                     # top-level umbrella, not a query test file
    "test_forward_chainer.metta",     # forward chaining out of scope
    "test_distribution_values.metta", # distributional values out of scope
    "test_particle_values.metta",     # particle distributions out of scope
    "test_numeric_pattern_dist.metta",# distributional values out of scope
    "test_benchgen_metta.metta",      # benchmark generator, not a chainer test
}

# Tests already converted by hand in converted_tests.metta.
SKIP_ALREADY = {
    "test_nary_conjuction.metta",
    "test_stv_implication_derived_ctv.metta",
    "test_implication_inversion.metta",
}


def tokenize(text):
    toks = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == ";":
            while i < n and text[i] != "\n":
                i += 1
        elif c in "()":
            toks.append(c)
            i += 1
        elif c == "!":
            toks.append("!")
            i += 1
        elif c.isspace():
            i += 1
        elif c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 1
            toks.append(text[i : j + 1])
            i = j + 1
        else:
            j = i
            while j < n and not text[j].isspace() and text[j] not in "();":
                j += 1
            toks.append(text[i:j])
            i = j
    return toks


def parse(toks):
    """Parse a token stream into a list of top-level forms.
    A form is ('bang', expr) or ('expr', expr); exprs are str or list."""
    forms = []
    pos = 0

    def parse_expr():
        nonlocal pos
        tok = toks[pos]
        if tok == "(":
            pos += 1
            items = []
            while toks[pos] != ")":
                items.append(parse_expr())
            pos += 1
            return items
        pos += 1
        return tok

    while pos < len(toks):
        if toks[pos] == "!":
            pos += 1
            forms.append(("bang", parse_expr()))
        else:
            forms.append(("expr", parse_expr()))
    return forms


def show(e):
    if isinstance(e, str):
        return e
    return "(" + " ".join(show(x) for x in e) + ")"


def head(e):
    return e[0] if isinstance(e, list) and e else None


def rename_calls(e):
    """Rename compileadd/query calls anywhere in an expression."""
    if not isinstance(e, list):
        return e
    e = [rename_calls(x) for x in e]
    if head(e) == "compileadd":
        e[0] = "mm2-compileadd"
    elif head(e) == "query":
        e[0] = "mm2-query"
    return e


def is_result(e):
    return head(e) == ":"


def normalize_expected(e):
    if e == []:
        return []
    if is_result(e):
        return [e]
    return e


def convert_test(expr):
    """(test QUERYISH EXPECTED) -> (mm2-test-query N kb pattern EXPECTED-LIST) or None."""
    if head(expr) != "test" or len(expr) != 3:
        return None
    queryish, expected = expr[1], expr[2]
    if head(queryish) == "collapse" and len(queryish) == 2:
        queryish = queryish[1]
    if head(queryish) != "query" or len(queryish) != 4:
        return None  # unsupported test form; caller passes through
    return [
        "mm2-test-query",
        rename_calls(queryish[1]),
        rename_calls(queryish[2]),
        rename_calls(queryish[3]),
        normalize_expected(rename_calls(expected)),
    ]


def convert_import(expr):
    if head(expr) != "import!" or len(expr) != 3:
        return None
    target = expr[2]
    if target == "petta_chainer":
        return None
    if isinstance(target, str) and target.startswith("logic_configs/"):
        return ["import!", expr[1], str(PETTA_METTA_DIR / target)]
    return None


def convert_file(path):
    forms = parse(tokenize(path.read_text()))
    out = [
        f"; generated from PeTTaChainer tests/{path.name} by convert_petta_tests.py",
        f"!(import! &self {HARNESS})",
        "!(mm2-init)",
    ]
    unsupported = 0
    for kind, expr in forms:
        if kind == "bang" and head(expr) == "import!":
            converted = convert_import(expr)
            if converted is not None:
                out.append("!" + show(converted))
            continue
        if kind == "bang" and head(expr) == "test":
            converted = convert_test(expr)
            if converted is not None:
                out.append("!" + show(converted))
                continue
            unsupported += 1
            out.append("; UNSUPPORTED test form: " + show(expr)[:160])
            snippet = re.sub(r"[^A-Za-z0-9_ /.$-]", " ", show(expr))[:80].strip()
            out.append(f'!(mm2-test-unsupported "{snippet}")')
            continue
        prefix = "!" if kind == "bang" else ""
        out.append(prefix + show(rename_calls(expr)))
    return "\n".join(out) + "\n", unsupported


def main():
    DST_DIR.mkdir(parents=True, exist_ok=True)
    total = 0
    for path in sorted(SRC_DIR.glob("test_*.metta")):
        if path.name in SKIP_FILES or path.name in SKIP_ALREADY:
            continue
        text, unsupported = convert_file(path)
        dst = DST_DIR / path.name
        dst.write_text(text)
        total += 1
        note = f" ({unsupported} unsupported test forms)" if unsupported else ""
        print(f"converted {path.name}{note}")
    print(f"{total} files -> {DST_DIR}")


if __name__ == "__main__":
    main()
