# CLI Usage and Configuration

Masque provides a command-line interface executable located at `zig-out/bin/masque` after building.

---

## Command Syntax

```bash
./zig-out/bin/masque [OPTIONS]
```

---

## Options & Flags Reference

| Option | Type | Default | Description |
|---|---|---|---|
| `--source` | `synthetic` \| `udp` \| `webcam` \| `stream` | `synthetic` | Selects video frame ingestion backend. |
| `--webcam` / `--no-webcam` | flag | off | Toggles the built-in webcam on or off. `--source`, `--webcam` and `--no-webcam` are last-wins, so `--no-webcam` can override an alias or script that passes `--webcam`. |
| `--webcam-device` | string | `0` (macOS), `/dev/video0` (Linux) | Camera to capture from. avfoundation index on macOS, device path on Linux, DirectShow device name on Windows (required there). |
| `--list-webcams` | flag | - | Lists the cameras ffmpeg can see and exits. |
| `--stream-url` | string | - | Any input ffmpeg can open (RTSP, HTTP MJPEG, HLS, local file). Implies `--source stream`; cannot be combined with `--webcam`. |
| `--ffmpeg` | path | `ffmpeg` | ffmpeg executable used by the `webcam` and `stream` sources. |
| `--fps` | integer | `30` | Stream execution rate (frames per second). |
| `--width` | integer | `640` | Video frame width in pixels. |
| `--height` | integer | `480` | Video frame height in pixels. |
| `--udp-in-port` | integer | `8888` | Port to bind for incoming video frames (when `--source udp`). |
| `--osc-host` | string (IP) | `127.0.0.1` | Destination IP address for OSC packets. |
| `--osc-port` | integer | `9000` | Destination UDP port for OSC packets. |
| `--osc-prefix` | string | `v2` | Parameter path prefix (`/avatar/parameters/<prefix>/...`). |
| `--binary` | flag | *disabled* | Encodes parameters as quantized binary bits instead of floats. |
| `--frames` | integer | *unlimited* | Maximum frames to process before cleanly exiting. |
| `--dry-run` | flag | `false` | Runs tracking pipeline without transmitting network UDP packets. |
| `--dump-osc` | flag | `false` | Prints live tracking metrics and parameters to `stdout`. |
| `--help`, `-h` | flag | - | Prints CLI help text and usage examples. |

---

## Practical Deployment Scenarios

### 1. Local Testing with Synthetic Animation
Streams procedurally animated face movements to the local VRCFaceTracking daemon:

```bash
./zig-out/bin/masque --dump-osc
```

### 2. Built-in Webcam
Requires [ffmpeg](https://ffmpeg.org) on `PATH` (`brew install ffmpeg`, `apt install ffmpeg`, or `winget install ffmpeg`).

```bash
# Default camera
./zig-out/bin/masque --webcam --dump-osc

# Choose a specific camera
./zig-out/bin/masque --list-webcams
./zig-out/bin/masque --webcam --webcam-device 1                         # macOS
./zig-out/bin/masque --webcam --webcam-device /dev/video2               # Linux
./zig-out/bin/masque --webcam --webcam-device "Integrated Camera"       # Windows
```

On macOS the first run triggers a camera permission prompt for your terminal app (System Settings → Privacy & Security → Camera).

The tracker uses fixed facial regions (see [Video Ingestion and Tracking](Video-Ingestion-and-Tracking)), so frame your face so it fills the image, centered, with even front lighting.

### 3. External Streaming Source
Use any camera or stream ffmpeg can decode instead of the built-in webcam:

```bash
./zig-out/bin/masque --stream-url rtsp://192.168.1.50:8554/face
./zig-out/bin/masque --stream-url http://192.168.1.60:8080/video.mjpg
./zig-out/bin/masque --stream-url recording.mp4 --dry-run --dump-osc
```

### 4. Live Wireless Headset / Ingest Server
Binds UDP port 8888 to receive incoming video frames from an external camera streamer and relays OSC data to VRChat on port 9000:

```bash
./zig-out/bin/masque --source udp --udp-in-port 8888 --osc-host 127.0.0.1 --osc-port 9000
```

### 5. Avatar Memory-Constrained Binary Mode
When using an avatar that uses 4-bit binary parameter quantization:

```bash
./zig-out/bin/masque --binary --dump-osc
```

### 6. Benchmark & Regression Pipeline Verification
Runs 300 frames in dry-run mode to benchmark performance and verify memory stability:

```bash
./zig-out/bin/masque --frames 300 --fps 60 --dry-run
```

---

## Integration with VRCFaceTracking & VRChat

1. **VRCFaceTracking Standalone Mode**:
   Set `--osc-host 127.0.0.1 --osc-port 9000`. VRCFaceTracking listens on UDP 9000 by default and relays calibrated avatar parameters directly to VRChat.
2. **Direct VRChat OSC Mode**:
   If bypassing the VRCFT intermediate app, send directly to VRChat's incoming OSC listener on `127.0.0.1:9000` with the standard `/avatar/parameters/v2/...` addressing scheme.
