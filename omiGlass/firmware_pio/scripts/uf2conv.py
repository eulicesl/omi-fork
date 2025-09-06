#!/usr/bin/env python3
"""
This is a placeholder for the UF2 conversion script.  The Omi Glass
firmware uses UF2 to produce a drag‑and‑drop binary for the ESP32‑S3
based Seeed XIAO board.  To generate a UF2 file you will need a
conversion tool that accepts a compiled binary and outputs a UF2
image.

We recommend fetching the `uf2conv.py` script from the original Omi
Glass firmware repository (see `firmware/build_uf2.sh` for an
example).  Alternatively, you can use the official MicroPython
`uf2conv.py` tool or the UF2 converter from Microsoft's UF2
repository.  Place the script in this directory to enable the
PlatformIO post‑build step defined in `make_uf2.py`.
"""

raise SystemExit(
    "uf2conv.py is a placeholder. Please provide a UF2 converter here "
    "or adjust make_uf2.py to use your own converter."
)
