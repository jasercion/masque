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
| `--source` | `synthetic` \| `udp` | `synthetic` | Selects video frame ingestion backend. |
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

### 2. Live Wireless Headset / Ingest Server
Binds UDP port 8888 to receive incoming video frames from an external camera streamer and relays OSC data to VRChat on port 9000:

```bash
./zig-out/bin/masque --source udp --udp-in-port 8888 --osc-host 127.0.0.1 --osc-port 9000
```

### 3. Avatar Memory-Constrained Binary Mode
When using an avatar that uses 4-bit binary parameter quantization:

```bash
./zig-out/bin/masque --binary --dump-osc
```

### 4. Benchmark & Regression Pipeline Verification
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
