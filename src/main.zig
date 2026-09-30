const std = @import("std");
const masque = @import("masque");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var source_type: []const u8 = "synthetic";
    var fps: u32 = 30;
    var width: u32 = 640;
    var height: u32 = 480;
    var udp_in_port: u16 = 8888;
    var osc_host: []const u8 = "127.0.0.1";
    var osc_port: u16 = 9000;
    var osc_prefix: []const u8 = "v2";
    var is_binary: bool = false;
    var dry_run: bool = false;
    var dump_osc: bool = false;
    var frame_limit: ?usize = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printHelp();
            return;
        } else if (std.mem.eql(u8, arg, "--source") and i + 1 < args.len) {
            i += 1;
            source_type = args[i];
        } else if (std.mem.eql(u8, arg, "--fps") and i + 1 < args.len) {
            i += 1;
            fps = try std.fmt.parseInt(u32, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--width") and i + 1 < args.len) {
            i += 1;
            width = try std.fmt.parseInt(u32, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--height") and i + 1 < args.len) {
            i += 1;
            height = try std.fmt.parseInt(u32, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--udp-in-port") and i + 1 < args.len) {
            i += 1;
            udp_in_port = try std.fmt.parseInt(u16, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--osc-host") and i + 1 < args.len) {
            i += 1;
            osc_host = args[i];
        } else if (std.mem.eql(u8, arg, "--osc-port") and i + 1 < args.len) {
            i += 1;
            osc_port = try std.fmt.parseInt(u16, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--osc-prefix") and i + 1 < args.len) {
            i += 1;
            osc_prefix = args[i];
        } else if (std.mem.eql(u8, arg, "--binary")) {
            is_binary = true;
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            dry_run = true;
        } else if (std.mem.eql(u8, arg, "--dump-osc")) {
            dump_osc = true;
        } else if (std.mem.eql(u8, arg, "--frames") and i + 1 < args.len) {
            i += 1;
            frame_limit = try std.fmt.parseInt(usize, args[i], 10);
        }
    }

    std.debug.print("====================================================\n", .{});
    std.debug.print("  MASQUE - Streaming Video to VRCFT (docs.vrcft.io)  \n", .{});
    std.debug.print("====================================================\n", .{});
    std.debug.print("Video Source : {s} ({d}x{d} @ {d} FPS)\n", .{ source_type, width, height, fps });
    std.debug.print("OSC Output   : {s}:{d} (prefix: '{s}', mode: {s})\n", .{
        osc_host,
        osc_port,
        osc_prefix,
        if (is_binary) "binary" else "float",
    });
    if (dry_run) std.debug.print("Dry Run      : Enabled (Network TX disabled)\n", .{});
    std.debug.print("----------------------------------------------------\n", .{});

    // 1. Initialize Stream Source
    var synthetic_source: ?masque.video.SyntheticSource = null;
    var udp_source: ?masque.video.UdpFrameSource = null;

    var stream: masque.video.StreamSource = undefined;

    if (std.mem.eql(u8, source_type, "udp")) {
        std.debug.print("Binding UDP video receiver on port {d}...\n", .{udp_in_port});
        udp_source = try masque.video.UdpFrameSource.init(arena, udp_in_port, width, height);
        stream = udp_source.?.source();
    } else {
        std.debug.print("Initializing synthetic facial simulation generator...\n", .{});
        synthetic_source = try masque.video.SyntheticSource.init(arena, width, height, fps);
        stream = synthetic_source.?.source();
    }

    // 2. Initialize VRCFT OSC Encoder and Transmitter
    const encoder = masque.vrcft.VrcftOscEncoder{
        .config = .{
            .base_prefix = "/avatar/parameters",
            .v2_subpath = osc_prefix,
        },
        .output_mode = if (is_binary) .binary_parameters else .float_parameters,
    };

    var maybe_transmitter: ?masque.vrcft.OscTransmitter = null;
    if (!dry_run) {
        maybe_transmitter = try masque.vrcft.OscTransmitter.init(
            arena,
            osc_host,
            osc_port,
            encoder,
        );
    }
    defer {
        if (maybe_transmitter) |*tx| tx.deinit();
    }

    // 3. Initialize Tracking Pipeline
    var tracker = masque.tracking.FaceTracker.init(arena);
    defer tracker.deinit();

    var current_data = masque.UnifiedTrackingData.init();
    var frames_processed: usize = 0;
    var total_bytes_sent: usize = 0;

    std.debug.print("Streaming pipeline running. Press Ctrl+C to terminate.\n", .{});

    while (true) {
        if (frame_limit) |limit| {
            if (frames_processed >= limit) break;
        }

        const maybe_frame = try stream.nextFrame(arena);
        if (maybe_frame == null) break;

        var frame = maybe_frame.?;
        defer frame.deinit();

        try tracker.processFrame(&frame, &current_data);
        frames_processed += 1;

        if (maybe_transmitter) |*tx| {
            const bytes_sent = try tx.sendTrackingData(&current_data);
            total_bytes_sent += bytes_sent;
        }

        if (dump_osc or frames_processed % 30 == 0) {
            std.debug.print(
                "[Frame {d: >5}] JawOpen: {d:.2} | EyeLookOutL: {d:.2} | EyeClosedL: {d:.2} | BrowUp: {d:.2} | Sent: {d} bytes\n",
                .{
                    frames_processed,
                    current_data.get(.JawOpen),
                    current_data.get(.EyeLookOutLeft),
                    current_data.get(.EyeClosedLeft),
                    current_data.get(.BrowUp),
                    total_bytes_sent,
                },
            );
        }

        // Throttle frame processing according to FPS
        if (std.mem.eql(u8, source_type, "synthetic")) {
            const sleep_ns = std.time.ns_per_s / fps;
            const ts = std.c.timespec{
                .sec = @intCast(sleep_ns / std.time.ns_per_s),
                .nsec = @intCast(sleep_ns % std.time.ns_per_s),
            };
            _ = std.c.nanosleep(&ts, null);
        }
    }

    std.debug.print("----------------------------------------------------\n", .{});
    std.debug.print("Finished processing {d} frames ({d} total bytes transmitted).\n", .{
        frames_processed,
        total_bytes_sent,
    });
}

fn printHelp() void {
    std.debug.print(
        \\Usage: masque [options]
        \\
        \\Options:
        \\  -h, --help            Show this help text
        \\  --source <type>       Video stream source: 'synthetic' (default) or 'udp'
        \\  --fps <int>           Target stream frame rate (default: 30)
        \\  --width <int>         Stream width in pixels (default: 640)
        \\  --height <int>        Stream height in pixels (default: 480)
        \\  --udp-in-port <int>   UDP incoming video stream port (default: 8888)
        \\  --osc-host <ip>       Destination OSC host address (default: 127.0.0.1)
        \\  --osc-port <int>      Destination OSC port (default: 9000)
        \\  --osc-prefix <str>    Unified Expressions OSC subpath (default: 'v2')
        \\  --binary              Output binary parameter format instead of float
        \\  --frames <int>        Process a fixed number of frames and exit
        \\  --dry-run             Run tracking without sending UDP packets
        \\  --dump-osc            Print every frame's tracked parameters
        \\
        \\VRCFT Standards Reference: https://docs.vrcft.io
        \\
    , .{});
}
