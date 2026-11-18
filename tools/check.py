"""Build and run the standalone GEMV and RTL checks."""

import argparse
import os
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
RTL_CASES = {
    "tb_arithmetic": ("multiplier.v", "mac.v"),
    "tb_icache": ("cache_line_ram.v", "ICache.v"),
    "tb_dcache": ("cache_line_ram.v", "DCache.v"),
}


def check_gemv(cc):
    binary = "build/gemv.exe" if os.name == "nt" else "build/gemv"
    subprocess.run(
        [cc, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
         "sw/demo.c", "sw/gemv_ref.c", "-o", binary],
        cwd=ROOT, check=True, timeout=60,
    )
    subprocess.run([str(ROOT / binary)], cwd=ROOT, check=True, timeout=20)


def check_rtl(waves):
    for top, sources in RTL_CASES.items():
        output = f"{top}.vvp"
        subprocess.run(
            ["iverilog", "-g2012", "-Wall", "-s", top, "-o", f"build/{output}",
             f"tests/{top}.sv", *(f"rtl/{src}" for src in sources)],
            cwd=ROOT, check=True, timeout=60,
        )
        wave_args = ["+waves"] if waves else []
        subprocess.run(["vvp", output, *wave_args], cwd=BUILD, check=True, timeout=30)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", nargs="?", default="all", choices=("all", "gemv", "rtl"))
    parser.add_argument("--cc", default=os.environ.get("CC", "gcc"))
    parser.add_argument("--waves", action="store_true", help="write RTL waveforms under build/")
    args = parser.parse_args()

    BUILD.mkdir(exist_ok=True)
    try:
        if args.target in ("all", "gemv"):
            check_gemv(args.cc)
        if args.target in ("all", "rtl"):
            check_rtl(args.waves)
    except (OSError, subprocess.SubprocessError) as error:
        print(f"Check failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
