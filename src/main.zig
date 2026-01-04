const rl = @import("raylib");

const Rectangle = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

const GameConfig = struct {
    // Player dimensions
    player_width: f32 = 28,
    player_height: f32 = 14,
    player_speed: f32 = 300,

    // Placement
    bottom_margin: f32 = 20,

    // Gun geometry (total protrusion = 7px via 4+3)
    gun_casing_w: f32 = 6,
    gun_casing_h: f32 = 4,
    gun_barrel_w: f32 = 3,
    gun_barrel_h: f32 = 3,
};

const Player = struct {
    rect: Rectangle,

    pub fn init(cfg: GameConfig, screen_w: f32, screen_h: f32) Player {
        return .{
            .rect = .{
                .x = (screen_w - cfg.player_width) / 2.0,
                .y = screen_h - cfg.player_height - cfg.bottom_margin,
                .width = cfg.player_width,
                .height = cfg.player_height,
            },
        };
    }

    pub fn update(self: *Player, cfg: GameConfig, dt: f32, screen_w: f32) void {
        var dir: f32 = 0.0;
        if (rl.isKeyDown(.left) or rl.isKeyDown(.a)) dir -= 1.0;
        if (rl.isKeyDown(.right) or rl.isKeyDown(.d)) dir += 1.0;

        self.rect.x += dir * cfg.player_speed * dt;
        self.clampX(screen_w);
    }

    pub fn anchorBottom(self: *Player, cfg: GameConfig, screen_h: f32) void {
        self.rect.y = screen_h - cfg.player_height - cfg.bottom_margin;
    }

    pub fn clampX(self: *Player, screen_w: f32) void {
        const min_x: f32 = 0.0;
        const max_x: f32 = screen_w - self.rect.width;
        if (self.rect.x < min_x) self.rect.x = min_x;
        if (self.rect.x > max_x) self.rect.x = max_x;
    }

    // Preserve relative X position when screen width changes.
    pub fn rescaleXForWidthChange(self: *Player, old_w: f32, new_w: f32) void {
        const old_max: f32 = old_w - self.rect.width;
        const new_max: f32 = new_w - self.rect.width;

        // If old_max is zero/negative, there was no horizontal room; just clamp.
        if (old_max <= 0 or new_max <= 0) {
            self.clampX(new_w);
            return;
        }

        // fraction in [0,1] across usable width
        const frac: f32 = self.rect.x / old_max;

        self.rect.x = frac * new_max;
        self.clampX(new_w);
    }

    pub fn draw(self: Player, cfg: GameConfig) void {
        // Player body
        rl.drawRectangle(
            @as(i32, @intFromFloat(self.rect.x)),
            @as(i32, @intFromFloat(self.rect.y)),
            @as(i32, @intFromFloat(self.rect.width)),
            @as(i32, @intFromFloat(self.rect.height)),
            rl.Color.green,
        );

        // Gun (centered on top of player)
        const cx = self.rect.x + self.rect.width / 2.0;
        const top = self.rect.y;

        const casing_x = cx - cfg.gun_casing_w / 2.0;
        const casing_y = top - cfg.gun_casing_h;

        rl.drawRectangle(
            @as(i32, @intFromFloat(casing_x)),
            @as(i32, @intFromFloat(casing_y)),
            @as(i32, @intFromFloat(cfg.gun_casing_w)),
            @as(i32, @intFromFloat(cfg.gun_casing_h)),
            rl.Color.green,
        );

        const barrel_x = cx - cfg.gun_barrel_w / 2.0;
        const barrel_y = casing_y - cfg.gun_barrel_h;

        rl.drawRectangle(
            @as(i32, @intFromFloat(barrel_x)),
            @as(i32, @intFromFloat(barrel_y)),
            @as(i32, @intFromFloat(cfg.gun_barrel_w)),
            @as(i32, @intFromFloat(cfg.gun_barrel_h)),
            rl.Color.lime,
        );
    }
};

pub fn main() void {
    const cfg = GameConfig{};

    rl.initWindow(800, 600, "zig-invaders");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var screen_w: f32 = @as(f32, @floatFromInt(rl.getScreenWidth()));
    var screen_h: f32 = @as(f32, @floatFromInt(rl.getScreenHeight()));

    var prev_screen_w: f32 = screen_w;

    var player = Player.init(cfg, screen_w, screen_h);

    while (!rl.windowShouldClose()) {
        const dt: f32 = rl.getFrameTime();

        // update runtime size
        screen_w = @as(f32, @floatFromInt(rl.getScreenWidth()));
        screen_h = @as(f32, @floatFromInt(rl.getScreenHeight()));

        // If width changed, preserve relative X position
        if (screen_w != prev_screen_w) {
            player.rescaleXForWidthChange(prev_screen_w, screen_w);
            prev_screen_w = screen_w;
        }

        player.anchorBottom(cfg, screen_h);
        player.update(cfg, dt, screen_w);

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);
        rl.drawText("Zig Invaders", 20, 20, 24, rl.Color.white);

        player.draw(cfg);
    }
}
