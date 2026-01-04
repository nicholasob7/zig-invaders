const rl: type = @import("raylib");

const Rectangle = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub fn right(self: Rectangle) f32 {
        return self.x + self.width;
    }
};

const GameConfig = struct {
    // Logical defaults (initial window size). Runtime uses getScreenWidth/Height every frame.
    screen_width: i32 = 800,
    screen_height: i32 = 600,

    // Player
    player_width: f32 = 26,
    player_height: f32 = 14,
    player_speed: f32 = 300,

    // Gun (must not protrude more than 7px above player)
    gun_protrude_max: f32 = 7,
    gun_casing_w: f32 = 6,
    gun_casing_h: f32 = 7,
    gun_barrel_w: f32 = 2,
    gun_barrel_h: f32 = 7,
};

fn clamp01(x: f32) f32 {
    if (x < 0) return 0;
    if (x > 1) return 1;
    return x;
}

fn clamp(x: f32, lo: f32, hi: f32) f32 {
    if (x < lo) return lo;
    if (x > hi) return hi;
    return x;
}

pub fn main() void {
    const cfg = GameConfig{};

    rl.initWindow(cfg.screen_width, cfg.screen_height, "zig-invaders");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    // Start centred (relative position = 0.5)
    var player = Rectangle{
        .x = (@as(f32, @floatFromInt(cfg.screen_width)) - cfg.player_width) / 2.0,
        .y = 0, // set on first frame from live screen height
        .width = cfg.player_width,
        .height = cfg.player_height,
    };

    // Maintain relative X across resizes/fullscreen moves
    var player_rel_x: f32 = 0.5;

    var prev_sw: i32 = 0;
    var prev_sh: i32 = 0;

    while (!rl.windowShouldClose()) {
        const dt: f32 = rl.getFrameTime();

        const sw_i: i32 = rl.getScreenWidth();
        const sh_i: i32 = rl.getScreenHeight();
        const sw: f32 = @as(f32, @floatFromInt(sw_i));
        const sh: f32 = @as(f32, @floatFromInt(sh_i));

        // Detect resize / monitor move; reapply relative X
        if (sw_i != prev_sw or sh_i != prev_sh) {
            prev_sw = sw_i;
            prev_sh = sh_i;

            const max_x: f32 = sw - player.width;
            player.x = clamp(player_rel_x * max_x, 0, max_x);
        }

        // Input
        var dx: f32 = 0;
        if (rl.isKeyDown(.left) or rl.isKeyDown(.a)) dx -= 1;
        if (rl.isKeyDown(.right) or rl.isKeyDown(.d)) dx += 1;

        if (dx != 0) {
            player.x += dx * cfg.player_speed * dt;
        }

        // Clamp inside current screen
        const max_x: f32 = sw - player.width;
        player.x = clamp(player.x, 0, max_x);

        // Update relative X for future resizes
        if (max_x > 0) {
            player_rel_x = clamp01(player.x / max_x);
        } else {
            player_rel_x = 0.0;
        }

        // Bottom safety margin scales with screen height (different monitors/taskbars)
        const safe_bottom: f32 = @max(24.0, @min(96.0, sh * 0.06)); // 6% height, clamped
        player.y = sh - player.height - safe_bottom;

        // ---- Gun geometry (attached to top-centre; protrude <= 7px) ----
        // Casing sits on top of player; barrel sits on top of casing.
        const casing_w: f32 = cfg.gun_casing_w;
        const casing_h: f32 = clamp(cfg.gun_casing_h, 0, cfg.gun_protrude_max);
        const barrel_w: f32 = cfg.gun_barrel_w;

        // Barrel can be shorter to keep total protrusion <= max
        const barrel_h: f32 = clamp(cfg.gun_barrel_h, 0, cfg.gun_protrude_max - casing_h);

        const player_center_x: f32 = player.x + player.width / 2.0;

        const casing_x: f32 = player_center_x - casing_w / 2.0;
        const casing_y: f32 = player.y - casing_h;

        const barrel_x: f32 = player_center_x - barrel_w / 2.0;
        const barrel_y: f32 = casing_y - barrel_h;

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);
        rl.drawText("Zig Invaders", 20, 20, 24, rl.Color.white);

        // Player body
        rl.drawRectangle(
            @as(i32, @intFromFloat(player.x)),
            @as(i32, @intFromFloat(player.y)),
            @as(i32, @intFromFloat(player.width)),
            @as(i32, @intFromFloat(player.height)),
            rl.Color.green,
        );

        // Gun casing (slightly thicker)
        rl.drawRectangle(
            @as(i32, @intFromFloat(casing_x)),
            @as(i32, @intFromFloat(casing_y)),
            @as(i32, @intFromFloat(casing_w)),
            @as(i32, @intFromFloat(casing_h)),
            rl.Color.green,
        );

        // Gun barrel (thin)
        rl.drawRectangle(
            @as(i32, @intFromFloat(barrel_x)),
            @as(i32, @intFromFloat(barrel_y)),
            @as(i32, @intFromFloat(barrel_w)),
            @as(i32, @intFromFloat(barrel_h)),
            rl.Color.green,
        );
    }
}
