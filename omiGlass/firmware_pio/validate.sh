#!/bin/bash
# Validation script for Omi Glass UF2 firmware build setup

echo "🔍 Validating Omi Glass UF2 firmware build setup..."

# Check if we're in the right directory
if [ ! -f "platformio.ini" ]; then
    echo "❌ Error: platformio.ini not found. Run this from omiGlass/firmware_pio directory"
    exit 1
fi

echo "✅ PlatformIO configuration found"

# Check source code
if [ ! -f "src/main.cpp" ]; then
    echo "❌ Error: src/main.cpp not found"
    exit 1
fi

echo "✅ Source code found"

# Check UF2 conversion script
if [ ! -f "scripts/uf2conv.py" ]; then
    echo "❌ Error: scripts/uf2conv.py not found"
    exit 1
fi

# Check if it's not a placeholder
if grep -q "placeholder" scripts/uf2conv.py; then
    echo "❌ Error: uf2conv.py is still a placeholder"
    exit 1
fi

echo "✅ UF2 conversion script ready"

# Check UF2 families file
if [ ! -f "scripts/uf2families.json" ]; then
    echo "❌ Error: scripts/uf2families.json not found"
    exit 1
fi

echo "✅ UF2 families configuration found"

# Check ESP32S3 support
if ! grep -q "ESP32S3" scripts/uf2families.json; then
    echo "❌ Error: ESP32S3 family not supported"
    exit 1
fi

echo "✅ ESP32S3 family support confirmed"

# Check post-build script
if [ ! -f "scripts/make_uf2.py" ]; then
    echo "❌ Error: scripts/make_uf2.py not found"
    exit 1
fi

echo "✅ Post-build UF2 script found"

# Test UF2 conversion script
output=$(python3 scripts/uf2conv.py -f ESP32S3 2>&1)
if [[ $? -ne 1 || ! "$output" =~ "Need input file" ]]; then
    echo "❌ Error: UF2 conversion script test failed"
    exit 1
fi

echo "✅ UF2 conversion script working"

echo ""
echo "🎉 All checks passed! The firmware build setup is ready."
echo ""
echo "To build manually:"
echo "  pio run -e uf2_release"
echo ""
echo "To use GitHub workflow:"
echo "  1. Go to Actions tab in GitHub"
echo "  2. Find 'Omi Glass UF2 (PlatformIO)' workflow"
echo "  3. Click 'Run workflow'"
echo "  4. Select 'feature/glass-audio-opus-ble-pio' branch"
echo "  5. Download 'omi-glass-firmware-uf2' artifact when complete"