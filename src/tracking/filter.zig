const std = @import("std");

/// Exponential Moving Average (EMA) Filter
pub const EmaFilter = struct {
    alpha: f32,
    value: ?f32 = null,

    pub fn init(alpha: f32) EmaFilter {
        return .{
            .alpha = std.math.clamp(alpha, 0.0, 1.0),
        };
    }

    pub fn filter(self: *EmaFilter, new_val: f32) f32 {
        if (self.value) |current| {
            const smoothed = self.alpha * new_val + (1.0 - self.alpha) * current;
            self.value = smoothed;
            return smoothed;
        } else {
            self.value = new_val;
            return new_val;
        }
    }

    pub fn reset(self: *EmaFilter) void {
        self.value = null;
    }
};

/// 1€ (One Euro) Filter for low-latency, adaptive jitter-reduction in tracking signals.
pub const OneEuroFilter = struct {
    min_cutoff: f32 = 1.0,
    beta: f32 = 0.007,
    d_cutoff: f32 = 1.0,
    x_prev: ?f32 = null,
    dx_prev: f32 = 0.0,
    t_prev: ?f64 = null,

    pub fn init(min_cutoff: f32, beta: f32) OneEuroFilter {
        return .{
            .min_cutoff = min_cutoff,
            .beta = beta,
        };
    }

    fn alpha(cutoff: f32, dt: f32) f32 {
        const tau = 1.0 / (2.0 * std.math.pi * cutoff);
        return 1.0 / (1.0 + tau / dt);
    }

    pub fn filter(self: *OneEuroFilter, x: f32, timestamp_s: f64) f32 {
        if (self.t_prev == null or self.x_prev == null) {
            self.x_prev = x;
            self.dx_prev = 0.0;
            self.t_prev = timestamp_s;
            return x;
        }

        const dt = @as(f32, @floatCast(timestamp_s - self.t_prev.?));
        if (dt <= 0.00001) return self.x_prev.?;

        // Estimate derivative
        const dx = (x - self.x_prev.?) / dt;
        const a_d = alpha(self.d_cutoff, dt);
        const dx_hat = a_d * dx + (1.0 - a_d) * self.dx_prev;

        // Filter signal with adaptive cutoff
        const cutoff = self.min_cutoff + self.beta * @abs(dx_hat);
        const a = alpha(cutoff, dt);
        const x_hat = a * x + (1.0 - a) * self.x_prev.?;

        self.x_prev = x_hat;
        self.dx_prev = dx_hat;
        self.t_prev = timestamp_s;

        return x_hat;
    }

    pub fn reset(self: *OneEuroFilter) void {
        self.x_prev = null;
        self.dx_prev = 0.0;
        self.t_prev = null;
    }
};

test "ema filter smoothing" {
    var ema = EmaFilter.init(0.5);
    try std.testing.expectEqual(@as(f32, 10.0), ema.filter(10.0));
    try std.testing.expectEqual(@as(f32, 15.0), ema.filter(20.0));
}

test "one euro filter responsiveness" {
    var oe = OneEuroFilter.init(1.0, 0.01);
    const f1 = oe.filter(1.0, 0.0);
    const f2 = oe.filter(1.0, 0.033);
    const f3 = oe.filter(2.0, 0.066);

    try std.testing.expectEqual(@as(f32, 1.0), f1);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), f2, 0.001);
    try std.testing.expect(f3 > 1.0 and f3 <= 2.0);
}
