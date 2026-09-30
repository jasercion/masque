# Masque: Video Stream to VRCFaceTracking (VRCFT) in Zig

`masque` is a high-performance Zig project that ingests streaming video input (network UDP packets, MJPEG streams, or synthetic calibration generators), extracts eye and facial feature tracking metrics, and outputs formatted Open Sound Control (OSC) data conforming to the [VRCFaceTracking (VRCFT) standard](https://docs.vrcft.io).

## Features

- **Full Unified Expressions (UE) Specification**:
  - Implements all standard VRCFT Unified Expressions (Eye Gaze, Eyelids, Pupils, Eyebrows, Cheeks, Nose, Jaw, Lips, Mouth, and Tongue).
  - Automatically computes derived and blended shapes (e.g. `BrowInnerUp`, `BrowUp`, `LipPucker`, `MouthSmile`, `MouthOpen`) from base shapes.
- **VRCFT Dynamic Parameter Addressing**:
  - Encodes OSC messages to `/avatar/parameters/v2/<ParameterName>` (or configurable custom subpaths/prefixes).
  - Supports both **Float** (`0.0` - `1.0`) and **Binary** parameter representations (quantized bits + sign bit) as documented in the VRCFT avatar guidelines.
- **High-Performance OSC 1.0/1.1 Engine**:
  - Zero-allocation message and bundle serialization with 4-byte alignment and big-endian network encoding.
  - Automatic packet batching to conform to UDP MTU constraints.
- **Multi-Source Streaming Video Ingestion**:
  - `SyntheticSource`: Procedurally animated facial & eye tracking video generator for continuous headless testing and calibration.
  - `UdpFrameSource`: Low-latency UDP video frame receiver for wireless VR headsets and camera streams.
  - `MjpegScanner`: Extraction and inspection of JPEG frames and dimensions from streaming chunks.
- **Computer Vision & Signal Processing**:
  - Gaze vector tracking, pupil centroid localization, eyelid aspect ratio analysis, and mouth deformation extraction.
  - Adaptive 1€ (One Euro) and Exponential Moving Average (EMA) temporal smoothing filters to eliminate jitter while maintaining responsive saccade tracking.

## Project Structure

```
├── build.zig               # Zig build configuration
├── build.zig.zon           # Package manifest
└── src/
    ├── main.zig            # CLI executable entry point
    ├── root.zig            # Re-usable library API exports
    ├── pipeline.zig        # Streaming pipeline coordinator
    ├── vrcft/
    │   ├── expressions.zig # Unified Expressions schema & blendshapes
    │   ├── osc.zig         # OSC protocol & VRCFT parameter encoder
    │   └── transmitter.zig # UDP socket transmitter & packet batcher
    ├── video/
    │   ├── frame.zig       # Video frame buffer & format conversions
    │   ├── jpeg_lite.zig   # JPEG frame parser & dimension scanner
    │   └── stream.zig      # Stream sources (Synthetic, UDP, etc.)
    └── tracking/
        ├── filter.zig      # One Euro & EMA temporal smoothing filters
        ├── landmarks.zig   # 2D facial geometry & ROI layout
        └── tracker.zig     # Feature extraction & expression engine
```

## Building and Running

### Build & Run Tests
```bash
zig build test
```

### Build Executable
```bash
zig build -Doptimize=ReleaseFast
```

The compiled binary will be placed in `zig-out/bin/masque`.

### Run the Application

```bash
# Run with synthetic video stream sending OSC to local VRCFT (127.0.0.1:9000)
./zig-out/bin/masque

# Ingest live UDP video stream on port 8888 and send OSC to custom target
./zig-out/bin/masque --source udp --udp-in-port 8888 --osc-host 127.0.0.1 --osc-port 9000

# Use binary parameter mode for avatars with constrained parameter memory
./zig-out/bin/masque --binary --dump-osc

# Process 100 test frames and output metrics
./zig-out/bin/masque --frames 100 --dump-osc
```

## CLI Options

| Flag | Description | Default |
|------|-------------|---------|
| `--source <type>` | Video stream source (`synthetic` or `udp`) | `synthetic` |
| `--fps <int>` | Video stream frame rate | `30` |
| `--width <int>` | Frame width in pixels | `640` |
| `--height <int>` | Frame height in pixels | `480` |
| `--udp-in-port <int>` | Incoming UDP stream port | `8888` |
| `--osc-host <ip>` | Target VRCFT / VRChat OSC IP | `127.0.0.1` |
| `--osc-port <int>` | Target OSC port | `9000` |
| `--osc-prefix <str>` | Unified Expressions subpath | `v2` |
| `--binary` | Encode as VRCFT binary parameters | `false` (float) |
| `--frames <int>` | Process N frames and exit | unlimited |
| `--dry-run` | Run tracking without sending UDP packets | `false` |
| `--dump-osc` | Print real-time expression values | `false` |
