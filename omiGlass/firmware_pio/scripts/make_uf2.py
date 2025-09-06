Import("env")
import os, subprocess

# After the binary is built, convert it to UF2 format.
BIN = env.ElfToBin("$BUILD_DIR/${PROGNAME}", "$BUILD_DIR/${PROGNAME}")

def after_build(source, target, env):
    bin_path = os.path.join(env.subst("$BUILD_DIR"), env.subst("${PROGNAME}.bin"))
    uf2_path = os.path.join(env.subst("$BUILD_DIR"), env.subst("${PROGNAME}.uf2"))
    tool = os.path.join(env.subst("$PROJECT_DIR"), "scripts", "uf2conv.py")
    # Use UF2 converter to produce a drag‑and‑drop UF2 image for ESP32‑S3
    cmd = ["python3", tool, "--convert", bin_path, "--family", "ESP32S3", "--output", uf2_path]
    print("UF2:", " ".join(cmd))
    subprocess.check_call(cmd)

env.AddPostAction(BIN, after_build)
