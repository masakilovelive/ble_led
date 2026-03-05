#!/usr/bin/env python3
"""RCローパスフィルター計算ツール.

R1（入力側シリーズ抵抗）、R2（出力ノードに接続された負荷抵抗）、
およびCの組み合わせに関する主要な指標を計算する。
"""

from __future__ import annotations

import argparse
import cmath
import math
import re
from dataclasses import dataclass
from typing import Iterable, List, Sequence


SI_PREFIXES = {
    "t": 1e12,
    "g": 1e9,
    "meg": 1e6,
    "k": 1e3,
    "": 1.0,
    "m": 1e-3,
    "u": 1e-6,
    "\u00b5": 1e-6,
    "n": 1e-9,
    "p": 1e-12,
    "f": 1e-15,
}

VALUE_PATTERN = re.compile(
    r"^\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*([A-Za-z\u00b5\u03a9]*)\s*$"
)


class ValueErrorWithHint(ValueError):
    """入力値に関するヒント付き例外."""


def _normalize_suffix(raw_suffix: str) -> str:
    suffix = raw_suffix.lower()
    for token in ("ohm", "\u03c9", "farad", "f", "s", "hz"):
        suffix = suffix.replace(token, "")
    return suffix


def parse_value(text: str) -> float:
    """SI接頭辞入りの文字列を数値へ変換."""
    token = text.strip()
    if not token:
        raise ValueErrorWithHint("空文字は数値として解釈できません")
    if token.lower() in {"inf", "infinity"}:
        return math.inf

    match = VALUE_PATTERN.match(token)
    if not match:
        raise ValueErrorWithHint(f"数値として解釈できません: '{text}'")

    number_text, suffix = match.groups()
    number = float(number_text)
    suffix = _normalize_suffix(suffix)

    if suffix in SI_PREFIXES:
        return number * SI_PREFIXES[suffix]

    # 接頭辞が複数文字の場合（例: kohm, meg, na）に対応
    for prefix in sorted(SI_PREFIXES.keys(), key=len, reverse=True):
        if prefix and suffix.startswith(prefix):
            return number * SI_PREFIXES[prefix]

    raise ValueErrorWithHint(f"未対応の接頭辞です: '{suffix}'")


def pretty_si(value: float, unit: str) -> str:
    """SI接頭辞を用いた読みやすい表記."""
    if value == 0:
        return f"0 {unit}"
    abs_value = abs(value)
    for prefix, factor in (
        ("G", 1e9),
        ("M", 1e6),
        ("k", 1e3),
        ("", 1.0),
        ("m", 1e-3),
        ("u", 1e-6),
        ("n", 1e-9),
        ("p", 1e-12),
    ):
        if abs_value >= factor or factor == 1e-12:
            scaled = value / factor
            return f"{scaled:.4g} {prefix}{unit}".strip()
    return f"{value:.4g} {unit}"


@dataclass
class AnalysisResult:
    r1: float
    r2: float | None
    c: float
    r_th: float
    tau: float
    fc: float
    dc_gain: float


def analyze_filter(r1: float, c: float, r2: float | None) -> AnalysisResult:
    """R1, R2, Cから主要値を算出."""
    if r1 <= 0 or c <= 0:
        raise ValueErrorWithHint("R1およびCは正の値である必要があります")

    if r2 is None or math.isinf(r2):
        r_th = r1
        dc_gain = 1.0
        r2 = None
    else:
        if r2 <= 0:
            raise ValueErrorWithHint("R2は正の値である必要があります")
        r_th = (r1 * r2) / (r1 + r2)
        dc_gain = r2 / (r1 + r2)

    tau = r_th * c
    fc = 1.0 / (2 * math.pi * tau)
    return AnalysisResult(r1=r1, r2=r2, c=c, r_th=r_th, tau=tau, fc=fc, dc_gain=dc_gain)


def transfer_function(r1: float, c: float, r2: float | None, freq: float) -> complex:
    """指定周波数での伝達関数値."""
    if freq <= 0 or math.isinf(freq):
        raise ValueErrorWithHint("周波数は正の有限値である必要があります")

    omega = 2 * math.pi * freq
    z_c = complex(0, -1 / (omega * c))
    if r2 is None:
        z_parallel = z_c
    else:
        z_parallel = 1 / (1 / complex(r2, 0) + 1 / z_c)
    return z_parallel / (r1 + z_parallel)


def print_analysis(result: AnalysisResult) -> None:
    print("=== ローパスフィルター解析 ===")
    print(f"R1     : {pretty_si(result.r1, 'ohm')}")
    if result.r2 is None:
        print("R2     : 未接続（無限大）")
    else:
        print(f"R2     : {pretty_si(result.r2, 'ohm')}")
    print(f"C      : {pretty_si(result.c, 'F')}")
    print(f"R_th   : {pretty_si(result.r_th, 'ohm')}")
    print(f"tau(RC): {pretty_si(result.tau, 's')}")
    print(f"f_c    : {pretty_si(result.fc, 'Hz')}")
    print(f"DCゲイン: {result.dc_gain:.4f} V/V ({20*math.log10(result.dc_gain):.2f} dB)")


def print_frequency_table(
    r1: float, c: float, r2: float | None, freqs: Sequence[float]
) -> None:
    if not freqs:
        return
    print("\n--- 周波数特性 ---")
    header = f"{'Freq [Hz]':>12} | {'|H| [V/V]':>11} | {'dB':>8} | {'位相[deg]':>10}"
    print(header)
    print("-" * len(header))
    for freq in freqs:
        h = transfer_function(r1, c, r2, freq)
        magnitude = abs(h)
        db = 20 * math.log10(magnitude) if magnitude > 0 else -math.inf
        phase_deg = math.degrees(cmath.phase(h))
        print(f"{freq:12.4g} | {magnitude:11.4g} | {db:8.2f} | {phase_deg:10.2f}")


def resolve_missing_value(args: argparse.Namespace) -> None:
    r1 = parse_value(args.r1) if args.r1 else None
    r2 = parse_value(args.r2) if args.r2 else None
    c = parse_value(args.c) if args.c else None
    fc = args.fc

    unknowns = sum(1 for value in (r1, r2, c) if value is None)
    if unknowns != 1:
        raise ValueErrorWithHint("designモードではR1/R2/Cのうち1つだけ未指定にしてください")
    if fc is None or fc <= 0:
        raise ValueErrorWithHint("設計対象のf_cは正の値である必要があります")

    if c is None:
        if r1 is None:
            raise ValueErrorWithHint("Cを設計する場合はR1を指定してください")
        if r2 is None or math.isinf(r2):
            r_th = r1
        else:
            if r2 <= 0:
                raise ValueErrorWithHint("R2は正の値である必要があります")
            r_th = (r1 * r2) / (r1 + r2)
        required_c = 1.0 / (2 * math.pi * fc * r_th)
        print(f"必要なC : {pretty_si(required_c, 'F')}")
        return

    if r2 is None:
        if r1 is None:
            raise ValueErrorWithHint("R2を設計する場合はR1を指定してください")
        r_th_target = 1.0 / (2 * math.pi * fc * c)
        if r1 <= r_th_target:
            raise ValueErrorWithHint("R1より小さいR_thは実現できません。R1またはf_cを見直してください")
        r2_needed = (r_th_target * r1) / (r1 - r_th_target)
        print(f"必要なR2: {pretty_si(r2_needed, 'ohm')}")
        return

    # 残りはR1が未知
    r_th_target = 1.0 / (2 * math.pi * fc * c)
    if r2 <= r_th_target:
        raise ValueErrorWithHint("R2より小さいR_thは実現できません。R2またはf_cを見直してください")
    r1_needed = (r_th_target * r2) / (r2 - r_th_target)
    print(f"必要なR1: {pretty_si(r1_needed, 'ohm')}")


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        description="RCローパスフィルター（R1, R2, C）の計算ツール",
    )
    subparsers = parser.add_subparsers(dest="command")

    analyze_parser = subparsers.add_parser(
        "analyze", help="R1/R2/Cからf_cや周波数特性を計算"
    )
    analyze_parser.add_argument("--r1", required=True, help="シリーズ抵抗R1 (例: 10k)")
    analyze_parser.add_argument(
        "--r2", help="負荷抵抗R2 (例: 47k)。未指定なら無限大として扱う"
    )
    analyze_parser.add_argument("--c", required=True, help="コンデンサC (例: 100n)")
    analyze_parser.add_argument(
        "--freq",
        dest="freqs",
        action="append",
        type=parse_value,
        help="任意の周波数点を指定（複数指定可）",
    )

    design_parser = subparsers.add_parser(
        "design", help="指定f_cを満たすよう未指定の1要素を算出"
    )
    design_parser.add_argument("--r1", help="既知のR1")
    design_parser.add_argument("--r2", help="既知のR2")
    design_parser.add_argument("--c", help="既知のC")
    design_parser.add_argument(
        "--fc", type=parse_value, required=True, help="ターゲットカットオフ周波数"
    )

    args = parser.parse_args(argv)

    try:
        if args.command == "design":
            resolve_missing_value(args)
        else:
            r1 = parse_value(args.r1)
            c = parse_value(args.c)
            r2 = parse_value(args.r2) if args.r2 else None
            result = analyze_filter(r1, c, r2)
            print_analysis(result)
            freq_list: List[float] = args.freqs if args.freqs else []
            print_frequency_table(result.r1, result.c, result.r2, freq_list)
    except ValueErrorWithHint as exc:  # noqa: PERF203 - clarity優先
        print(f"エラー: {exc}")
        raise SystemExit(1)


if __name__ == "__main__":
    main()
