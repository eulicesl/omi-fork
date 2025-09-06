# Omi Glass UF2 Firmware (PlatformIO)

This directory contains the PlatformIO-based firmware for Omi Glass devices built on the Seeed XIAO ESP32-S3 Sense platform.

## Features

- **Camera**: On-board OV2640 camera configured at 640×480 with JPEG compression
- **Audio**: PDM microphone sampled at 16 kHz mono via I2S, encoded using OPUS codec (~16 kbps)
- **Connectivity**: Bluetooth BLE for data streaming
- **Build Output**: UF2 format for drag-and-drop flashing

## GitHub Workflow Usage

### Automatic Builds

The firmware is automatically built when pushing to:
- `feature/glass-audio-opus-ble-pio` branch
- `main` branch (if firmware files are modified)

### Manual Builds

1. **Navigate to Actions**: Go to the GitHub repository's "Actions" tab
2. **Find Workflow**: Look for "Omi Glass UF2 (PlatformIO)" workflow
3. **Run Workflow**:
   - Click "Run workflow"
   - Select branch: `feature/glass-audio-opus-ble-pio`
   - Click "Run workflow" button
4. **Wait for Build**: The job takes 1-2 minutes to complete
5. **Download Artifact**:
   - Once complete, click on the workflow run
   - Download the `omi-glass-firmware-uf2` artifact
   - Extract to get `firmware.uf2` file

## Local Development

### Prerequisites

- Python 3.x
- PlatformIO Core

### Setup

```bash
# Install PlatformIO
pip install platformio

# Navigate to firmware directory
cd omiGlass/firmware_pio

# Build for release
pio run -e uf2_release
```

### Output

The build produces:
- `firmware.bin` - Raw binary
- `firmware.uf2` - UF2 format for drag-and-drop flashing

## Hardware Configuration

- **Board**: Seeed XIAO ESP32-S3 Sense
- **Flash Mode**: QIO
- **Flash Size**: 8MB
- **PSRAM**: Enabled
- **Upload Protocol**: ESP Tool

## BLE Services

The firmware implements BLE services compatible with the Omi mobile app:
- **Photo Capture**: Short button press → JPEG delivery via PHOTO_DATA UUID
- **Audio Recording**: Long button press or BLE control via AUDIO_CTRL UUID
- **Audio Streaming**: OPUS packets via AUDIO_DATA UUID

## Dependencies

- `pschatzmann/arduino-libopus @ ^0.2.3` - OPUS audio encoding
- `pschatzmann/arduino-audio-tools @ ^1.0.12` - Audio processing utilities
- ESP32 Arduino Framework with camera and BLE support