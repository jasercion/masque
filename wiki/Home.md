# Home

Welcome to the **Masque** wiki!

`masque` is a high-performance, zero-overhead [Zig](https://ziglang.org) library and CLI tool designed to ingest real-time streaming video, extract facial and ocular tracking features via computer vision heuristics, and dispatch Open Sound Control (OSC) data conforming to the [VRCFaceTracking (VRCFT) Unified Expressions](https://docs.vrcft.io) standard.

---

## Key Capabilities

* **Full Unified Expressions Standard (UE)**: Native support for all 80+ standard Unified Expressions blendshapes across eye gaze, eyelids, pupils, eyebrows, cheeks, jaw, lips, and tongue.
* **Automatic Shape Synthesis**: Derives blended and compound shape keys (e.g. `BrowInnerUp`, `MouthSmile`, `LipPucker`) from isolated base geometric displacements.
* **VRCFT OSC 1.0/1.1 Dynamic Addressing**: Serializes messages using `/avatar/parameters/v2/<ParameterName>` with both **32-bit Float** (`0.0`–`1.0`) and **Quantized Binary Bits** (`*1`, `*2`, `*4`, `*8` + sign bit) encoding.
* **Low-Latency Network & Video Ingestion**: Non-blocking UDP video frame streaming, zero-allocation MJPEG header and boundary scanning, and procedural synthetic animation generation for headless calibration and testing.
* **Temporal Signal Smoothing**: 1€ (One Euro) adaptive filtering and Exponential Moving Average (EMA) to eliminate high-frequency sensor noise while preserving saccadic ocular responsiveness.
* **Deterministic Resource Allocation**: Strict Zig memory allocation model with zero garbage collection overhead and deterministic teardown.

---

## Wiki Contents

Explore the documentation pages below:

1. **[Architecture and Data Flow](Architecture-and-Data-Flow)**  
   System design, pipeline stages, memory layout, and the end-to-end data transformation pipeline from video frames to network datagrams.

2. **[API Reference](API-Reference)**  
   Detailed documentation for all public library modules: `masque.vrcft`, `masque.video`, `masque.tracking`, and `masque.pipeline`.

3. **[Unified Expressions and OSC Protocol](Unified-Expressions-and-OSC)**  
   The Unified Expressions schema, base & derived blendshape mathematical models, OSC 1.0/1.1 message & bundle encoding, and binary parameter quantization.

4. **[Video Ingestion and Tracking](Video-Ingestion-and-Tracking)**  
   Frame representation, luminance extraction, network stream reassembly, computer vision tracking algorithms, and adaptive temporal filters.

5. **[CLI Usage and Configuration](CLI-Usage-and-Configuration)**  
   Executable flags, network configuration, parameter prefixes, diagnostic logging, and VRCFaceTracking / VRChat integration.

6. **[Development and Testing](Development-and-Testing)**  
   Build instructions, test execution, benchmarks, adding custom tracking sources, and guidelines for contributing.

---

## Quick Start

### Build from Source

Ensure you have Zig (0.13.0 or later / master) installed:

```bash
# Build release executable
zig build -Doptimize=ReleaseFast

# Run test suite
zig build test
```

### Run Masque

```bash
# Stream procedurally generated tracking data to local VRCFaceTracking (UDP 127.0.0.1:9000)
./zig-out/bin/masque --dump-osc

# Ingest wireless camera frames over UDP port 8888 and forward OSC
./zig-out/bin/masque --source udp --udp-in-port 8888 --osc-host 127.0.0.1 --osc-port 9000
```
