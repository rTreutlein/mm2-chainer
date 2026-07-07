#!/usr/bin/env python3
"""Reference implementation of PeTTaChainer TV formulas for computing
expected values in mm2-chainer regression tests.

Mirrors PeTTaChainer/pettachainer/metta/tv_formulas.metta and the
Rust ports in MORK kernel/src/pure.rs + sinks.rs. All math is plain
IEEE-754 double precision in the same operation order as the Rust code.
"""

K = 800.0


def confidence_to_count(c):
    # chainer_utils.metta:149 — c*800/(1 - min(c, 0.9999))
    if c <= 0.0:
        return 0.0
    return 800.0 * c / (1.0 - min(c, 0.9999))


def count_confidence(n):
    return n / (n + K)


def ideal_clip(s):
    return max(0.000001, min(0.999999, s))


def ideal_var(s, c):
    cs = ideal_clip(s)
    return cs * (1.0 - cs) / (confidence_to_count(c) + 1.0)


def ideal_conf_from_var(s, var):
    if var <= 0.0:
        return 0.9999
    cs = ideal_clip(s)
    maxvar = cs * (1.0 - cs)
    n = maxvar / min(var, maxvar) - 1.0
    return max(0.000001, n / (n + K))


def and_formula(tv1, tv2):
    """AndFormula: fold two premise STVs."""
    s1, c1 = tv1
    s2, c2 = tv2
    s = s1 * s2
    if c1 <= 0.0 or c2 <= 0.0:
        return (s, 0.0)
    v1 = ideal_var(s1, c1)
    v2 = ideal_var(s2, c2)
    var = v1 * v2 + v1 * s2 * s2 + s1 * s1 * v2
    return (s, ideal_conf_from_var(s, var))


def and_fold(tvs):
    """Fold premise TVs left-to-right like the mm2 premise frontier."""
    acc = tvs[0]
    for tv in tvs[1:]:
        acc = and_formula(acc, tv)
    return acc


def negative_branch_strength(sa, sb, sb_a):
    if sa >= 1.0:
        return sb
    return max(0.0, min(1.0, (sb - sa * sb_a) / (1.0 - sa)))


def heuristic_negative_branch(atv, btv, pos):
    sa, ca = atv
    sb, cb = btv
    s, c = pos
    return (negative_branch_strength(sa, sb, s), 0.25 * min(ca, cb, c))


def derived_ctv(atv, btv, pos):
    """ImplicationCTVFormula for a plain STV rule. atv/btv are the base
    rates of antecedent/consequent; no-evidence is (0.0, 0.0)."""
    return (pos, heuristic_negative_branch(atv, btv, pos))


def ideal_mp_confidence(as_, ac, bs_a, bc_a, bs_na, bc_na):
    va = ideal_var(bs_a, bc_a)
    vna = ideal_var(bs_na, bc_na)
    vz = ideal_var(as_, ac)
    vars_b = (
        (as_ * as_) * va
        + ((1.0 - as_) * (1.0 - as_)) * vna
        + ((bs_a - bs_na) * (bs_a - bs_na)) * vz
        + vz * (va + vna)
    )
    s_b = bs_a * as_ + bs_na * (1.0 - as_)
    return ideal_conf_from_var(s_b, vars_b)


def modus_ponens(atv, ctv):
    """CTVModusPonensFormula: premise aggregate TV + rule CTV -> proof TV."""
    (bs_a, bc_a), (bs_na, bc_na) = ctv
    as_, ac = atv
    s = bs_a * as_ + bs_na * (1.0 - as_)
    return (s, ideal_mp_confidence(as_, ac, bs_a, bc_a, bs_na, bc_na))


def base_rate(fact_tvs):
    """Weighted base rate over facts matching a pattern; no-evidence -> (0,0)."""
    wsum = 0.0
    csum = 0.0
    for s, c in fact_tvs:
        wsum += s * c
        csum += c
    if csum <= 0.0:
        return (0.0, 0.0)
    return (wsum / csum, count_confidence(csum))


def inversion_smallest_intersection(sa, sb):
    return max(0.0, (sa + sb - 1.0) / sa)


def inversion_largest_intersection(sa, sb):
    return min(1.0, sb / sa)


def inversion_consistent(atv, btv, pos):
    sa = atv[0]
    sb = btv[0]
    sb_a = pos[0]
    if sa <= 0.0 or sb <= 0.0:
        return False
    return (
        inversion_smallest_intersection(sa, sb) <= sb_a
        and sb_a <= inversion_largest_intersection(sa, sb)
    )


def ideal_ratio_var(p, vp, sa, vsa, q, vq):
    d1 = sa / q
    d2 = p / q
    d3 = (p * sa) / (q * q)
    return (d1 * d1) * vp + (d2 * d2) * vsa + (d3 * d3) * vq


def ctv_inversion(atv, btv, ctv):
    """CTVInversionFormula: invert an implication's CTV using the base rates
    of its antecedent (atv) and consequent (btv). Returns None when the
    inversion is rejected (no evidence, or inconsistent marginals)."""
    if atv == (0.0, 0.0) or btv == (0.0, 0.0):  # no-evidence
        return None
    (sb_a, cb_a), (_sb_na, _cb_na) = ctv
    sa, ca = atv
    sb, cb = btv
    if sb <= 0.0 or sb >= 1.0:
        return ((0.0, 0.0), (0.0, 0.0))
    if sa > 0.0 and not inversion_consistent(atv, btv, ctv[0]):
        return None
    va = ideal_var(sb_a, cb_a)
    vsa = ideal_var(sa, ca)
    vsb = ideal_var(sb, cb)
    s_pos = min(1.0, (sb_a * sa) / sb)
    s_neg = min(1.0, ((1.0 - sb_a) * sa) / (1.0 - sb))
    return (
        (s_pos, ideal_conf_from_var(s_pos, ideal_ratio_var(sb_a, va, sa, vsa, sb, vsb))),
        (
            s_neg,
            ideal_conf_from_var(
                s_neg, ideal_ratio_var(1.0 - sb_a, va, sa, vsa, 1.0 - sb, vsb)
            ),
        ),
    )


def and_projection(tv_ab, tv_a):
    """AndProjection: element TV of a compound And given the other elements'
    evidence TV (tv_formulas.metta)."""
    sab, cab = tv_ab
    sa, ca = tv_a
    if sa == 0.0:
        return (0.0, 0.0)
    return (min(1.0, sab / sa), min(cab, ca))


def or_projection(tv_ab, tv_a):
    sab, cab = tv_ab
    sa, ca = tv_a
    if sa == 1.0:
        return (0.0, 0.0)
    return (min(1.0, max(0.0, (sab - sa) / (1.0 - sa))), min(cab, ca))


def and_marginal_projection(tv_ab):
    sab, cab = tv_ab
    return (sab, count_confidence(sab * confidence_to_count(cab)))


def not_formula(tv):
    s, c = tv
    return (1.0 - s, c)


def revise(old, new):
    """revise_stv from MORK sinks.rs (merge two proofs of one fact)."""
    old_s, old_c = old
    new_s, new_c = new
    old_n = confidence_to_count(old_c)
    new_n = confidence_to_count(new_c)
    total = old_n + new_n
    s = 0.0 if total == 0.0 else (old_s * old_n + new_s * new_n) / total
    return (s, total / (total + K))


def fmt(tv):
    return f"({tv[0]} {tv[1]})"


if __name__ == "__main__":
    # Sanity checks against known PeTTaChainer expected values.
    exact = (1.0, 1.0)

    got = and_fold([exact, exact])
    assert got[1] == 0.9998000399670116, got
    got = and_fold([exact, exact, exact])
    assert got[1] == 0.999700089898053, got

    # test_stv_implication_derived_ctv: fact (A x) (1.0 0.9),
    # rule (STV 0.6 0.9), baserate(A)=fold[(1.0,0.9)], baserate(B)=none.
    br_a = base_rate([(1.0, 0.9)])
    br_b = base_rate([])
    ctv = derived_ctv(br_a, br_b, (0.6, 0.9))
    got = modus_ponens((1.0, 0.9), ctv)
    assert got == (0.6, 0.8999998649685302), got

    # test_backward_open_query_results first case: premise (1.0 1.0),
    # rule CTV ((1.0 1.0) (0.0 1.0)).
    got = modus_ponens(exact, ((1.0, 1.0), (0.0, 1.0)))
    assert got == (1.0, 0.9998000399670116), got

    print("pln_ref: all sanity checks pass")
