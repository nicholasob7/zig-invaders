const std = @import("std");
const rl: type = @import("raylib");

const MaxBullets = 10;
const BaseCount = 5;
const BaseColumns = 13;
const BaseRows = 7;
const BaseTemplate = [_]u16{
    0b0011111111100,
    0b0111111111110,
    0b1111111111111,
    0b1111111111111,
    0b1111111111111,
    0b1111000001111,
    0b1110000000111,
};
const InvaderColumns = 11;
const InvaderRows = 8;
const InvaderGridRows = 5;
const InvaderGridCols = 11;
const InvaderSprite = struct {
    rows: [InvaderRows]u16,
};
const InvaderSpriteTop = InvaderSprite{
    .rows = .{
        0b00011111000,
        0b00111111100,
        0b01110011110,
        0b01111111110,
        0b00111111100,
        0b00011111000,
        0b00100000100,
        0b01000000010,
    },
};
const InvaderSpriteMid = InvaderSprite{
    .rows = .{
        0b00001111000,
        0b00111111100,
        0b01111111110,
        0b11101110111,
        0b11111111111,
        0b00100100100,
        0b01001001010,
        0b10010010001,
    },
};
const InvaderSpriteBot = InvaderSprite{
    .rows = .{
        0b00011111000,
        0b01111111110,
        0b11111111111,
        0b11011111011,
        0b11111111111,
        0b00111011100,
        0b01100110010,
        0b11000000111,
    },
};

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
    player_vertical_speed: f32 = 180,

    // Gun (must not protrude more than 7px above player)
    gun_protrude_max: f32 = 7,
    gun_casing_w: f32 = 6,
    gun_casing_h: f32 = 7,
    gun_barrel_w: f32 = 2,
    gun_barrel_h: f32 = 7,

    // Bullets
    bullet_speed: f32 = 520,
    bullet_radius: f32 = 2,
    bullet_length: f32 = 8,
    bullet_inherit_vx: f32 = 0.35,
    bullet_curve_drag: f32 = 2.6,

    // Grenade
    grenade_speed_y: f32 = 360,
    grenade_radius: f32 = 3,
    grenade_inherit_vx: f32 = 0.55,
    grenade_gravity: f32 = 650,
    grenade_arc_speed_threshold: f32 = 1.0,
    grenade_arc_max_deg: f32 = 3.0,
    grenade_cooldown_s: f32 = 5.0,
    grenade_fuse_s: f32 = 1.6,
    grenade_explosion_s: f32 = 0.35,
    grenade_explosion_radius_min: f32 = 24,
    grenade_explosion_radius_max: f32 = 72,
    grenade_marker_s: f32 = 0.45,

    // Invaders
    invader_cell_size: f32 = 3,
    invader_spacing: f32 = 6,
    invader_speed: f32 = 32,
    invader_drop: f32 = 16,
    invader_bullet_speed: f32 = 180,
};

const Bullet = struct {
    x: f32 = 0,
    y: f32 = 0,
    vx: f32 = 0,
    vy: f32 = 0,
    active: bool = false,
};

const Grenade = struct {
    x: f32 = 0,
    y: f32 = 0,
    vx: f32 = 0,
    vy: f32 = 0,
    launch_x: f32 = 0,
    flight_time: f32 = 0,
    active: bool = false,
    cooldown: f32 = 0,
    explosion_timer: f32 = 0,
    explosion_x: f32 = 0,
    explosion_y: f32 = 0,
};

const Invader = struct {
    alive: bool = true,
};

const EnemyBullet = struct {
    x: f32 = 0,
    y: f32 = 0,
    vy: f32 = 0,
    active: bool = false,
    squiggly: bool = false,
    age: f32 = 0,
};

const ExplosionDebris = struct {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
};

const ExplosionMarker = struct {
    x: f32 = 0,
    y: f32 = 0,
    timer: f32 = 0,
    active: bool = false,
    burst_angles: [6]f32 = [_]f32{0} ** 6,
    debris: [6]ExplosionDebris = [_]ExplosionDebris{.{ .x = 0, .y = 0, .vx = 0, .vy = 0 }} ** 6,
};

const Base = struct {
    x: f32 = 0,
    y: f32 = 0,
    cell_size: f32 = 1,
    cells: [BaseRows]u16 = BaseTemplate,
};

const GameState = enum {
    playing,
    player_down,
    level_clear,
    game_over,
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

    // Maintain relative X (centered) across resizes/fullscreen moves
    var player_rel_x: f32 = 0.5;

    var prev_sw: i32 = 0;
    var prev_sh: i32 = 0;
    var baseline_set = false;
    var baseline_y: f32 = 0;

    var bullets: [MaxBullets]Bullet = [_]Bullet{.{}} ** MaxBullets;
    var grenade = Grenade{};
    var bases: [BaseCount]Base = [_]Base{.{}} ** BaseCount;
    var invaders: [InvaderGridRows][InvaderGridCols]Invader = [_][InvaderGridCols]Invader{[_]Invader{.{}} ** InvaderGridCols} ** InvaderGridRows;
    var enemy_bullets: [24]EnemyBullet = [_]EnemyBullet{.{}} ** 24;
    var invader_dir: f32 = 1.0;
    var invader_offset_x: f32 = 0;
    var invader_offset_y: f32 = 0;
    var invader_fire_timer: f32 = 0;
    var invader_shots_in_burst: u8 = 0;
    var invader_speed_scale: f32 = 1.0;
    var prng = std.Random.DefaultPrng.init(0x124a_1f2b);
    var markers: [12]ExplosionMarker = [_]ExplosionMarker{.{}} ** 12;
    var player_hit_streak: u8 = 0;
    var squiggly_death_pending = false;
    var state: GameState = .playing;
    var lives_remaining: u8 = 3;
    var level: u32 = 1;

    const base_area: f32 = cfg.player_width * cfg.player_height * 5.0;
    const base_cell_size: f32 = std.math.sqrt(base_area / @as(f32, BaseColumns * BaseRows));
    const base_width: f32 = base_cell_size * BaseColumns;
    const base_height: f32 = base_cell_size * BaseRows;
    for (&bases) |*base| {
        base.cell_size = base_cell_size;
        base.cells = BaseTemplate;
    }

    while (!rl.windowShouldClose()) {
        const dt: f32 = rl.getFrameTime();
        const sw_i: i32 = rl.getScreenWidth();
        const sh_i: i32 = rl.getScreenHeight();
        const sw: f32 = @as(f32, @floatFromInt(sw_i));
        const sh: f32 = @as(f32, @floatFromInt(sh_i));
        const is_playing = state == .playing;

        // Detect resize / monitor move; reapply relative X
        const resized = sw_i != prev_sw or sh_i != prev_sh;
        if (resized) {
            prev_sw = sw_i;
            prev_sh = sh_i;

            const max_x: f32 = sw - player.width;
            const target_x: f32 = player_rel_x * sw - player.width * 0.5;
            player.x = clamp(target_x, 0, max_x);
        }

        // Input
        var dx: f32 = 0;
        if (is_playing) {
            if (rl.isKeyDown(.left) or rl.isKeyDown(.a)) dx -= 1;
            if (rl.isKeyDown(.right) or rl.isKeyDown(.d)) dx += 1;
        }

        const player_vel_x: f32 = dx * cfg.player_speed;
        const prev_player_x: f32 = player.x;
        if (dx != 0) {
            player.x += player_vel_x * dt;
        }

        // Clamp inside current screen
        const max_x: f32 = sw - player.width;
        player.x = clamp(player.x, 0, max_x);

        // Update relative X for future resizes
        if (sw > 0) {
            const player_center = player.x + player.width * 0.5;
            player_rel_x = clamp01(player_center / sw);
        } else {
            player_rel_x = 0.5;
        }

        // Bottom safety margin scales with screen height (different monitors/taskbars)
        const safe_bottom: f32 = @max(24.0, @min(96.0, sh * 0.06)); // 6% height, clamped
        baseline_y = sh - player.height - safe_bottom;
        if (!baseline_set) {
            player.y = baseline_y;
            baseline_set = true;
        } else if (resized or player.y > baseline_y) {
            player.y = baseline_y;
        }

        const bases_total: f32 = base_width * BaseCount;
        const gap: f32 = @max(0, (sw - bases_total) / @as(f32, BaseCount + 1));
        const base_y: f32 = baseline_y - player.height - base_height;
        for (&bases, 0..) |*base, idx| {
            base.y = base_y;
            base.x = gap + @as(f32, @floatFromInt(idx)) * (base_width + gap);
        }

        const invader_width: f32 = cfg.invader_cell_size * InvaderColumns;
        const invader_height: f32 = cfg.invader_cell_size * InvaderRows;
        const invader_step_x: f32 = invader_width + cfg.invader_spacing;
        const invader_step_y: f32 = invader_height + cfg.invader_spacing;
        const invader_group_width: f32 = invader_step_x * InvaderGridCols - cfg.invader_spacing;
        var invader_origin_x: f32 = (sw - invader_group_width) * 0.5 + invader_offset_x;
        var invader_origin_y: f32 = sh * 0.12 + invader_offset_y;
        var alive_count: usize = 0;
        if (is_playing) {
            for (invaders) |row| {
                for (row) |invader| {
                    if (invader.alive) {
                        alive_count += 1;
                    }
                }
            }
        }

        if (is_playing) {
            const total_invaders: f32 = @floatFromInt(InvaderGridRows * InvaderGridCols);
            const alive_ratio: f32 = if (alive_count > 0) @as(f32, @floatFromInt(alive_count)) / total_invaders else 0.0;
            const level_speed_bonus: f32 = if (level >= 4) 0.8 * 9.0 else if (level >= 3) 0.8 * 3.0 else if (level >= 2) 0.8 else 0.0;
            const level_speed_scale: f32 = 1.0 + (1.0 - alive_ratio) * level_speed_bonus;
            const effective_invader_speed_scale: f32 = invader_speed_scale * level_speed_scale;
            var alive_min_col: i32 = -1;
            var alive_max_col: i32 = -1;
            var row_idx: usize = 0;
            while (row_idx < InvaderGridRows) : (row_idx += 1) {
                var col_idx: usize = 0;
                while (col_idx < InvaderGridCols) : (col_idx += 1) {
                    if (!invaders[row_idx][col_idx].alive) continue;
                    const col_i32: i32 = @intCast(col_idx);
                    if (alive_min_col == -1 or col_i32 < alive_min_col) alive_min_col = col_i32;
                    if (alive_max_col == -1 or col_i32 > alive_max_col) alive_max_col = col_i32;
                }
            }

            if (alive_min_col != -1) {
                const left_edge = invader_origin_x + @as(f32, @floatFromInt(alive_min_col)) * invader_step_x;
                const right_edge = invader_origin_x + @as(f32, @floatFromInt(alive_max_col)) * invader_step_x + invader_width;
                if (left_edge <= 16 or right_edge >= sw - 16) {
                    invader_dir *= -1.0;
                    invader_offset_y += cfg.invader_drop * effective_invader_speed_scale;
                    invader_origin_x = (sw - invader_group_width) * 0.5 + invader_offset_x;
                    invader_origin_y = sh * 0.12 + invader_offset_y;
                }
            }
            invader_offset_x += invader_dir * cfg.invader_speed * effective_invader_speed_scale * dt;

            if (invader_fire_timer > 0) {
                invader_fire_timer = @max(0, invader_fire_timer - dt);
            }
        }

        var ceiling_y: f32 = base_y + (@as(f32, BaseRows - 2) * base_cell_size) - player.height;
        var has_base_overlap = false;
        for (bases) |base| {
            const player_left = player.x;
            const player_right = player.x + player.width;
            if (player_right <= base.x or player_left >= base.x + base_width) continue;
            has_base_overlap = true;

            const col_start_unclamped: i32 = @intFromFloat((player_left - base.x) / base.cell_size);
            const col_end_unclamped: i32 = @intFromFloat((player_right - base.x - 0.001) / base.cell_size);
            const col_start: usize = @intCast(@max(0, @min(@as(i32, BaseColumns - 1), col_start_unclamped)));
            const col_end: usize = @intCast(@max(0, @min(@as(i32, BaseColumns - 1), col_end_unclamped)));

            var row: usize = 0;
            var found = false;
            while (row < BaseRows) : (row += 1) {
                var col: usize = col_start;
                while (col <= col_end) : (col += 1) {
                    const bit: u16 = @as(u16, 1) << @as(u4, @intCast(col));
                    if ((base.cells[row] & bit) != 0) {
                        const row_bottom = base.y + (@as(f32, @floatFromInt(row + 1)) * base.cell_size);
                        ceiling_y = @min(ceiling_y, row_bottom - player.height);
                        found = true;
                        break;
                    }
                }
                if (found) break;
            }

            if (!found) {
                ceiling_y = @min(ceiling_y, base.y - player.height);
            }
        }
        if (!has_base_overlap) {
            ceiling_y = base_y + (@as(f32, BaseRows - 2) * base_cell_size) - player.height;
        }
        ceiling_y = @min(ceiling_y, baseline_y);

        if (is_playing) {
            if (rl.isKeyDown(.up)) {
                player.y = @max(ceiling_y, player.y - cfg.player_vertical_speed * dt);
            } else if (rl.isKeyDown(.down)) {
                player.y = @min(baseline_y, player.y + cfg.player_vertical_speed * dt);
            }
        }

        if (player.y < baseline_y) {
            const player_left = player.x;
            const player_right = player.x + player.width;
            const player_top = player.y;
            const player_bottom = player.y + player.height;
            var hit_base = false;
            for (bases) |base| {
                if (player_right <= base.x or player_left >= base.x + base_width) continue;
                if (player_bottom <= base.y or player_top >= base.y + base_height) continue;

                const col_start_unclamped: i32 = @intFromFloat((player_left - base.x) / base.cell_size);
                const col_end_unclamped: i32 = @intFromFloat((player_right - base.x - 0.001) / base.cell_size);
                const row_start_unclamped: i32 = @intFromFloat((player_top - base.y) / base.cell_size);
                const row_end_unclamped: i32 = @intFromFloat((player_bottom - base.y - 0.001) / base.cell_size);

                const col_start: usize = @intCast(@max(0, @min(@as(i32, BaseColumns - 1), col_start_unclamped)));
                const col_end: usize = @intCast(@max(0, @min(@as(i32, BaseColumns - 1), col_end_unclamped)));
                const row_start: usize = @intCast(@max(0, @min(@as(i32, BaseRows - 1), row_start_unclamped)));
                const row_end: usize = @intCast(@max(0, @min(@as(i32, BaseRows - 1), row_end_unclamped)));

                var row: usize = row_start;
                while (row <= row_end) : (row += 1) {
                    var col: usize = col_start;
                    while (col <= col_end) : (col += 1) {
                        const bit: u16 = @as(u16, 1) << @as(u4, @intCast(col));
                        if ((base.cells[row] & bit) != 0) {
                            hit_base = true;
                            break;
                        }
                    }
                    if (hit_base) break;
                }
                if (hit_base) break;
            }
            if (hit_base) {
                player.x = prev_player_x;
            }
        }

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

        const player_left = player.x;
        const player_right = player.x + player.width;
        const player_top = player.y;
        var overlaps_base = false;
        var barrel_protrudes = true;
        var shoulders_exposed = true;
        for (bases) |base| {
            if (player_right <= base.x or player_left >= base.x + base_width) continue;
            if (player_top + player.height <= base.y or player_top >= base.y + base_height) {
                continue;
            }

            overlaps_base = true;
            if (barrel_y >= base.y) {
                barrel_protrudes = false;
            }

            if (player_top >= base.y and player_top < base.y + base_height) {
                const col_start_unclamped: i32 = @intFromFloat((player_left - base.x) / base.cell_size);
                const col_end_unclamped: i32 = @intFromFloat((player_right - base.x - 0.001) / base.cell_size);
                const col_start: usize = @intCast(@max(0, @min(@as(i32, BaseColumns - 1), col_start_unclamped)));
                const col_end: usize = @intCast(@max(0, @min(@as(i32, BaseColumns - 1), col_end_unclamped)));
                const row: usize = @intCast(@max(0, @min(@as(i32, BaseRows - 1), @as(i32, @intFromFloat((player_top - base.y) / base.cell_size)))));

                var col: usize = col_start;
                while (col <= col_end) : (col += 1) {
                    const bit: u16 = @as(u16, 1) << @as(u4, @intCast(col));
                    if ((base.cells[row] & bit) != 0) {
                        shoulders_exposed = false;
                        break;
                    }
                }
            }
        }

        const can_fire = is_playing and ((!overlaps_base) or (barrel_protrudes and shoulders_exposed));
        const player_bullet_speed: f32 = if (level >= 4) cfg.bullet_speed * 1.5 else cfg.bullet_speed;
        const fire_pressed = rl.isKeyPressed(.v) or rl.isKeyPressed(.b);
        if (can_fire and fire_pressed) {
            for (&bullets) |*bullet| {
                if (!bullet.active) {
                    bullet.active = true;
                    bullet.x = player_center_x;
                    bullet.y = barrel_y;
                    bullet.vx = player_vel_x * cfg.bullet_inherit_vx;
                    bullet.vy = -player_bullet_speed;
                    break;
                }
            }
        }

        const grenade_pressed = rl.isKeyPressed(.z) or rl.isKeyPressed(.g);
        if (is_playing and !overlaps_base and grenade_pressed and !grenade.active and grenade.explosion_timer <= 0 and grenade.cooldown <= 0) {
            grenade.active = true;
            grenade.flight_time = 0;
            grenade.x = player_center_x;
            grenade.y = barrel_y;
            grenade.launch_x = player_center_x;
            var target_y: f32 = sh * 0.5;
            var lowest_alive: i32 = -1;
            var row_idx: usize = 0;
            while (row_idx < InvaderGridRows) : (row_idx += 1) {
                var col_idx: usize = 0;
                while (col_idx < InvaderGridCols) : (col_idx += 1) {
                    if (invaders[row_idx][col_idx].alive) {
                        lowest_alive = @as(i32, @intCast(row_idx));
                        break;
                    }
                }
            }
            if (lowest_alive >= 0) {
                const target_row = @max(0, lowest_alive - 1);
                target_y = invader_origin_y + @as(f32, @floatFromInt(target_row)) * invader_step_y + invader_height * 0.5;
            }
            grenade.vy = (target_y - grenade.y - 0.5 * cfg.grenade_gravity * cfg.grenade_fuse_s * cfg.grenade_fuse_s) / cfg.grenade_fuse_s;
            grenade.vx = 0;
        }

        if (is_playing) {
            if (grenade.cooldown > 0) {
                grenade.cooldown = @max(0, grenade.cooldown - dt);
            }

            if (grenade.explosion_timer > 0) {
                grenade.explosion_timer = @max(0, grenade.explosion_timer - dt);
            }

            for (&markers) |*marker| {
                if (!marker.active) continue;
                marker.timer -= dt;
                if (marker.timer <= 0) {
                    marker.active = false;
                    continue;
                }
                var i: usize = 0;
                while (i < marker.debris.len) : (i += 1) {
                    marker.debris[i].x += marker.debris[i].vx * dt;
                    marker.debris[i].y += marker.debris[i].vy * dt;
                }
            }

            if (invader_fire_timer <= 0) {
                if (alive_count > 0) {
                    const rng = prng.random();
                    var target_row: usize = 0;
                    var target_col: usize = 0;
                    if (invader_shots_in_burst == 4) {
                        var best_dist: f32 = 1e9;
                        var row_idx: usize = 0;
                        while (row_idx < InvaderGridRows) : (row_idx += 1) {
                            var col_idx: usize = 0;
                            while (col_idx < InvaderGridCols) : (col_idx += 1) {
                                if (!invaders[row_idx][col_idx].alive) continue;
                                const inv_x = invader_origin_x + @as(f32, @floatFromInt(col_idx)) * invader_step_x + invader_width * 0.5;
                                const dist = @abs(inv_x - player_center_x);
                                if (dist < best_dist) {
                                    best_dist = dist;
                                    target_row = row_idx;
                                    target_col = col_idx;
                                }
                            }
                        }
                    } else {
                        var alive_indices: [InvaderGridRows * InvaderGridCols]usize = undefined;
                        var alive_pick_count: usize = 0;
                        var row_idx: usize = 0;
                        while (row_idx < InvaderGridRows) : (row_idx += 1) {
                            var col_idx: usize = 0;
                            while (col_idx < InvaderGridCols) : (col_idx += 1) {
                                if (invaders[row_idx][col_idx].alive) {
                                    alive_indices[alive_pick_count] = row_idx * InvaderGridCols + col_idx;
                                    alive_pick_count += 1;
                                }
                            }
                        }
                        if (alive_pick_count > 0) {
                            const pick = rng.intRangeLessThan(usize, 0, alive_pick_count);
                            target_row = alive_indices[pick] / InvaderGridCols;
                            target_col = alive_indices[pick] % InvaderGridCols;
                        }
                    }

                    for (&enemy_bullets) |*shot| {
                        if (!shot.active) {
                            shot.active = true;
                            shot.squiggly = false;
                            shot.age = 0;
                            shot.vy = cfg.invader_bullet_speed;
                            shot.x = invader_origin_x + @as(f32, @floatFromInt(target_col)) * invader_step_x + invader_width * 0.5;
                            shot.y = invader_origin_y + @as(f32, @floatFromInt(target_row)) * invader_step_y + invader_height;
                            break;
                        }
                    }

                    invader_shots_in_burst += 1;
                    invader_fire_timer = 1.0 / 3.0;

                    if (invader_shots_in_burst >= 5) {
                        for (&enemy_bullets) |*shot| {
                            if (!shot.active) {
                                shot.active = true;
                                shot.squiggly = true;
                                shot.age = 0;
                                shot.vy = cfg.invader_bullet_speed * 1.6;
                                shot.x = invader_origin_x + @as(f32, @floatFromInt(target_col)) * invader_step_x + invader_width * 0.5;
                                shot.y = invader_origin_y + @as(f32, @floatFromInt(target_row)) * invader_step_y + invader_height;
                                break;
                            }
                        }
                        invader_shots_in_burst = 0;
                    }
                }
            }

            for (&bullets) |*bullet| {
                if (!bullet.active) continue;
                bullet.vx -= bullet.vx * cfg.bullet_curve_drag * dt;
                bullet.x += bullet.vx * dt;
                bullet.y += bullet.vy * dt;

                for (&bases) |*base| {
                    if (!bullet.active) break;
                    const local_x: f32 = bullet.x - base.x;
                    const local_y: f32 = bullet.y - base.y;
                    if (local_x < 0 or local_y < 0) continue;
                    if (local_x >= base_width or local_y >= base_height) continue;

                    const col: usize = @intFromFloat(local_x / base.cell_size);
                    const row: usize = @intFromFloat(local_y / base.cell_size);
                    if (row >= BaseRows or col >= BaseColumns) continue;

                    const bit: u16 = @as(u16, 1) << @as(u4, @intCast(col));
                    if ((base.cells[row] & bit) != 0) {
                        base.cells[row] &= ~bit;
                        bullet.active = false;
                    }
                }

                if (bullet.active) {
                    var row_idx: usize = 0;
                    while (row_idx < InvaderGridRows) : (row_idx += 1) {
                        var col_idx: usize = 0;
                        while (col_idx < InvaderGridCols) : (col_idx += 1) {
                            if (!invaders[row_idx][col_idx].alive) continue;
                            const inv_x = invader_origin_x + @as(f32, @floatFromInt(col_idx)) * invader_step_x;
                            const inv_y = invader_origin_y + @as(f32, @floatFromInt(row_idx)) * invader_step_y;
                            if (bullet.x >= inv_x and bullet.x <= inv_x + invader_width and bullet.y >= inv_y and bullet.y <= inv_y + invader_height) {
                                invaders[row_idx][col_idx].alive = false;
                                bullet.active = false;
                                break;
                            }
                        }
                        if (!bullet.active) break;
                    }
                }

                if (bullet.y + cfg.bullet_radius < 0 or bullet.x < -cfg.bullet_radius or bullet.x > sw + cfg.bullet_radius) {
                    bullet.active = false;
                }
            }

            for (&enemy_bullets) |*shot| {
                if (!shot.active) continue;
                shot.age += dt;
                shot.y += shot.vy * dt;

                for (&bases) |*base| {
                    if (!shot.active) break;
                    const local_x: f32 = shot.x - base.x;
                    const local_y: f32 = shot.y - base.y;
                    if (local_x < 0 or local_y < 0) continue;
                    if (local_x >= base_width or local_y >= base_height) continue;

                    const col: usize = @intFromFloat(local_x / base.cell_size);
                    const row: usize = @intFromFloat(local_y / base.cell_size);
                    if (row >= BaseRows or col >= BaseColumns) continue;

                    const bit: u16 = @as(u16, 1) << @as(u4, @intCast(col));
                    if ((base.cells[row] & bit) != 0) {
                        base.cells[row] &= ~bit;
                        if (shot.squiggly and row + 1 < BaseRows) {
                            base.cells[row + 1] &= ~bit;
                        }
                        shot.active = false;
                    }
                }

                if (shot.active and state == .playing) {
                    const wobble = if (shot.squiggly) std.math.sin(shot.age * 14.0) * 3.0 else 0.0;
                    const shot_x = shot.x + wobble;
                    if (shot_x >= player.x and shot_x <= player.x + player.width and shot.y >= player.y and shot.y <= player.y + player.height) {
                        shot.active = false;
                        if (squiggly_death_pending) {
                            squiggly_death_pending = false;
                            player_hit_streak = 0;
                            if (lives_remaining > 0) lives_remaining -= 1;
                            state = if (lives_remaining > 0) .player_down else .game_over;
                        } else {
                            player_hit_streak += 1;
                            if (player_hit_streak >= 4) {
                                player_hit_streak = 0;
                                squiggly_death_pending = false;
                                if (lives_remaining > 0) lives_remaining -= 1;
                                state = if (lives_remaining > 0) .player_down else .game_over;
                            } else if (shot.squiggly) {
                                squiggly_death_pending = true;
                            }
                        }
                    }
                }

                if (shot.y - cfg.bullet_length > sh) {
                    shot.active = false;
                }
            }

            const ground_y: f32 = sh - safe_bottom;
            if (grenade.active) {
                grenade.flight_time += dt;
                grenade.vy += cfg.grenade_gravity * dt;
                grenade.x = grenade.launch_x;
                grenade.y += grenade.vy * dt;

                if (grenade.y >= ground_y or grenade.flight_time >= cfg.grenade_fuse_s) {
                    grenade.active = false;
                    grenade.explosion_timer = cfg.grenade_explosion_s;
                    grenade.explosion_x = grenade.launch_x;
                    grenade.explosion_y = @min(grenade.y, ground_y);
                    grenade.cooldown = cfg.grenade_cooldown_s;
                    var lowest_row: i32 = -1;
                    const col_center_x = invader_origin_x + invader_width * 0.5;
                    const min_center_x = col_center_x;
                    const max_center_x = col_center_x + @as(f32, @floatFromInt(InvaderGridCols - 1)) * invader_step_x;
                    const launch_in_band = grenade.launch_x >= min_center_x - invader_step_x * 0.5 and grenade.launch_x <= max_center_x + invader_step_x * 0.5;
                    if (!launch_in_band) {
                        continue;
                    }
                    const col_f = (grenade.launch_x - col_center_x) / invader_step_x;
                    var center_col: i32 = @intFromFloat(@floor(col_f + 0.5));
                    center_col = @min(@max(center_col, 0), @as(i32, InvaderGridCols) - 1);
                    var row_idx: i32 = @as(i32, InvaderGridRows) - 1;
                    while (row_idx >= 0) : (row_idx -= 1) {
                        var col_idx: i32 = center_col - 1;
                        while (col_idx <= center_col + 1) : (col_idx += 1) {
                            if (col_idx < 0 or col_idx >= @as(i32, InvaderGridCols)) continue;
                            if (invaders[@intCast(row_idx)][@intCast(col_idx)].alive) {
                                lowest_row = row_idx;
                                break;
                            }
                        }
                        if (lowest_row >= 0) break;
                    }

                    if (lowest_row >= 0) {
                        var use_three_by_three = false;
                        if (lowest_row >= 1) {
                            var col_idx: i32 = center_col - 1;
                            while (col_idx <= center_col + 1) : (col_idx += 1) {
                                if (col_idx < 0 or col_idx >= @as(i32, InvaderGridCols)) continue;
                                if (invaders[@intCast(lowest_row - 1)][@intCast(col_idx)].alive) {
                                    use_three_by_three = true;
                                    break;
                                }
                            }
                        }

                        const grid_cols: i32 = if (use_three_by_three) 3 else 2;
                        const grid_rows: i32 = if (use_three_by_three) 3 else 2;
                        var row_start: i32 = if (use_three_by_three) lowest_row - 2 else lowest_row - 1;
                        if (row_start < 0) row_start = 0;
                        var col_start: i32 = 0;
                        if (use_three_by_three) {
                            col_start = center_col - 1;
                        } else {
                            const frac = col_f - @as(f32, @floatFromInt(center_col));
                            col_start = if (frac >= 0) center_col else center_col - 1;
                        }

                        var alive_positions: [9]u8 = undefined;
                        var alive_grid_count: usize = 0;
                        var r: i32 = row_start;
                        while (r < row_start + grid_rows) : (r += 1) {
                            var c: i32 = col_start;
                            while (c < col_start + grid_cols) : (c += 1) {
                                if (r < 0 or r >= @as(i32, InvaderGridRows) or c < 0 or c >= @as(i32, InvaderGridCols)) continue;
                                if (!invaders[@intCast(r)][@intCast(c)].alive) continue;
                                const pos = @as(u8, @intCast((r - row_start) * grid_cols + (c - col_start)));
                                alive_positions[alive_grid_count] = pos;
                                alive_grid_count += 1;
                            }
                        }

                        var pick_count: usize = if (use_three_by_three) 3 else 2;
                        if (alive_grid_count < pick_count) pick_count = alive_grid_count;

                        if (pick_count > 0) {
                            var rng = prng.random();
                            var idx: usize = 0;
                            while (idx < pick_count) : (idx += 1) {
                                const pick = rng.intRangeLessThan(usize, idx, alive_grid_count);
                                const swap = alive_positions[idx];
                                alive_positions[idx] = alive_positions[pick];
                                alive_positions[pick] = swap;
                            }

                            var killed_any = false;
                            idx = 0;
                            while (idx < pick_count) : (idx += 1) {
                                const pos = alive_positions[idx];
                                const grid_cols_usize: usize = @intCast(grid_cols);
                                const r_pick = row_start + @as(i32, @intCast(pos / grid_cols_usize));
                                const c_pick = col_start + @as(i32, @intCast(pos % grid_cols_usize));
                                if (!invaders[@intCast(r_pick)][@intCast(c_pick)].alive) continue;
                                invaders[@intCast(r_pick)][@intCast(c_pick)].alive = false;
                                killed_any = true;

                                const marker_x = invader_origin_x + @as(f32, @floatFromInt(c_pick)) * invader_step_x + invader_width * 0.5;
                                const marker_y = invader_origin_y + @as(f32, @floatFromInt(r_pick)) * invader_step_y + invader_height * 0.5;
                                for (&markers) |*marker| {
                                    if (!marker.active) {
                                        marker.active = true;
                                        marker.timer = cfg.grenade_marker_s;
                                        marker.x = marker_x;
                                        marker.y = marker_y;
                                        var j: usize = 0;
                                        while (j < marker.burst_angles.len) : (j += 1) {
                                            marker.burst_angles[j] = rng.float(f32) * std.math.tau;
                                        }
                                        j = 0;
                                        while (j < marker.debris.len) : (j += 1) {
                                            const angle = rng.float(f32) * std.math.tau;
                                            const speed = 30.0 + rng.float(f32) * 60.0;
                                            marker.debris[j] = .{
                                                .x = marker_x,
                                                .y = marker_y,
                                                .vx = @cos(angle) * speed,
                                                .vy = @sin(angle) * speed,
                                            };
                                        }
                                        break;
                                    }
                                }
                            }

                            if (killed_any) {
                                invader_speed_scale *= 1.0033;
                            }
                        }
                    }
                }
            }
        }

        if (state == .playing) {
            if (alive_count == 0) {
                state = .level_clear;
            }
        }

        if (state == .player_down and rl.isKeyPressed(.enter)) {
            player_hit_streak = 0;
            squiggly_death_pending = false;
            for (&bullets) |*bullet| bullet.* = .{};
            for (&enemy_bullets) |*shot| shot.* = .{};
            for (&markers) |*marker| marker.* = .{};
            grenade = .{};
            invader_fire_timer = 0;
            invader_shots_in_burst = 0;
            player.x = (sw - player.width) * 0.5;
            player.y = baseline_y;
            player_rel_x = 0.5;
            state = .playing;
        } else if (state == .game_over and rl.isKeyPressed(.r)) {
            lives_remaining = 3;
            level = 1;
            state = .playing;
            player_hit_streak = 0;
            squiggly_death_pending = false;
            for (&bullets) |*bullet| bullet.* = .{};
            for (&enemy_bullets) |*shot| shot.* = .{};
            for (&markers) |*marker| marker.* = .{};
            grenade = .{};
            invader_dir = 1.0;
            invader_offset_x = 0;
            invader_offset_y = 0;
            invader_fire_timer = 0;
            invader_shots_in_burst = 0;
            invader_speed_scale = 1.0;
            for (&invaders) |*row| {
                for (row) |*invader| invader.alive = true;
            }
            for (&bases) |*base| {
                base.cells = BaseTemplate;
            }
            player.x = (sw - player.width) * 0.5;
            player.y = baseline_y;
            player_rel_x = 0.5;
        } else if (state == .level_clear and rl.isKeyPressed(.n)) {
            level += 1;
            state = .playing;
            player_hit_streak = 0;
            squiggly_death_pending = false;
            for (&bullets) |*bullet| bullet.* = .{};
            for (&enemy_bullets) |*shot| shot.* = .{};
            for (&markers) |*marker| marker.* = .{};
            grenade = .{};
            invader_dir = 1.0;
            invader_offset_x = 0;
            invader_offset_y = 0;
            invader_fire_timer = 0;
            invader_shots_in_burst = 0;
            invader_speed_scale = 1.0;
            for (&invaders) |*row| {
                for (row) |*invader| invader.alive = true;
            }
            for (&bases) |*base| {
                base.cells = BaseTemplate;
            }
            player.x = (sw - player.width) * 0.5;
            player.y = baseline_y;
            player_rel_x = 0.5;
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);
        rl.drawText("Zig Invaders", 20, 20, 24, rl.Color.white);

        // Player body
        const player_dead = state == .player_down or state == .game_over;
        const player_color = if (player_dead) rl.Color.red else rl.Color.green;
        rl.drawRectangle(
            @as(i32, @intFromFloat(player.x)),
            @as(i32, @intFromFloat(player.y)),
            @as(i32, @intFromFloat(player.width)),
            @as(i32, @intFromFloat(player.height)),
            player_color,
        );

        const base_color = rl.Color{ .r = 80, .g = 200, .b = 80, .a = 255 };
        for (bases) |base| {
            var row: usize = 0;
            while (row < BaseRows) : (row += 1) {
                const row_mask = base.cells[row];
                var col: usize = 0;
                while (col < BaseColumns) : (col += 1) {
                    const bit: u16 = @as(u16, 1) << @as(u4, @intCast(col));
                    if ((row_mask & bit) == 0) continue;
                    rl.drawRectangle(
                        @as(i32, @intFromFloat(base.x + @as(f32, @floatFromInt(col)) * base.cell_size)),
                        @as(i32, @intFromFloat(base.y + @as(f32, @floatFromInt(row)) * base.cell_size)),
                        @as(i32, @intFromFloat(base.cell_size)),
                        @as(i32, @intFromFloat(base.cell_size)),
                        base_color,
                    );
                }
            }
        }

        const invader_colors = [_]rl.Color{
            rl.Color{ .r = 200, .g = 80, .b = 80, .a = 255 },
            rl.Color{ .r = 200, .g = 200, .b = 80, .a = 255 },
            rl.Color{ .r = 80, .g = 200, .b = 200, .a = 255 },
            rl.Color{ .r = 120, .g = 200, .b = 80, .a = 255 },
            rl.Color{ .r = 200, .g = 120, .b = 200, .a = 255 },
        };
        var row_idx: usize = 0;
        while (row_idx < InvaderGridRows) : (row_idx += 1) {
            var col_idx: usize = 0;
            while (col_idx < InvaderGridCols) : (col_idx += 1) {
                if (!invaders[row_idx][col_idx].alive) continue;
                const inv_x = invader_origin_x + @as(f32, @floatFromInt(col_idx)) * invader_step_x;
                const inv_y = invader_origin_y + @as(f32, @floatFromInt(row_idx)) * invader_step_y;
                const sprite = if (row_idx == 0) InvaderSpriteTop else if (row_idx <= 2) InvaderSpriteMid else InvaderSpriteBot;
                const color = invader_colors[row_idx];
                var sr: usize = 0;
                while (sr < InvaderRows) : (sr += 1) {
                    const mask = sprite.rows[sr];
                    var sc: usize = 0;
                    while (sc < InvaderColumns) : (sc += 1) {
                        const bit: u16 = @as(u16, 1) << @as(u4, @intCast(sc));
                        if ((mask & bit) == 0) continue;
                        rl.drawRectangle(
                            @as(i32, @intFromFloat(inv_x + @as(f32, @floatFromInt(sc)) * cfg.invader_cell_size)),
                            @as(i32, @intFromFloat(inv_y + @as(f32, @floatFromInt(sr)) * cfg.invader_cell_size)),
                            @as(i32, @intFromFloat(cfg.invader_cell_size)),
                            @as(i32, @intFromFloat(cfg.invader_cell_size)),
                            color,
                        );
                    }
                }
            }
        }

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

        for (bullets) |bullet| {
            if (!bullet.active) continue;
            const bullet_x: i32 = @as(i32, @intFromFloat(bullet.x));
            const bullet_y: i32 = @as(i32, @intFromFloat(bullet.y));
            const bullet_tail: i32 = @as(i32, @intFromFloat(bullet.y + cfg.bullet_length));
            rl.drawLine(
                bullet_x,
                bullet_y,
                bullet_x,
                bullet_tail,
                rl.Color.white,
            );
            rl.drawCircle(
                @as(i32, @intFromFloat(bullet.x)),
                @as(i32, @intFromFloat(bullet.y)),
                cfg.bullet_radius,
                rl.Color.white,
            );
        }

        for (enemy_bullets) |shot| {
            if (!shot.active) continue;
            const wobble = if (shot.squiggly) std.math.sin(shot.age * 14.0) * 3.0 else 0.0;
            const bullet_x: i32 = @as(i32, @intFromFloat(shot.x + wobble));
            const bullet_y: i32 = @as(i32, @intFromFloat(shot.y));
            const bullet_tail: i32 = @as(i32, @intFromFloat(shot.y + cfg.bullet_length));
            rl.drawLine(
                bullet_x,
                bullet_y,
                bullet_x,
                bullet_tail,
                if (shot.squiggly) rl.Color.orange else rl.Color.red,
            );
        }

        for (markers) |marker| {
            if (!marker.active) continue;
            const pulse = @max(0.0, marker.timer / cfg.grenade_marker_s);
            const radius = cfg.invader_cell_size * (2.0 + (1.0 - pulse));
            const core = rl.Color{ .r = 255, .g = 200, .b = 80, .a = @intCast(120 + @as(i32, @intFromFloat(120.0 * pulse))) };
            const rim = rl.Color{ .r = 255, .g = 140, .b = 0, .a = @intCast(80 + @as(i32, @intFromFloat(120.0 * pulse))) };
            rl.drawCircle(
                @as(i32, @intFromFloat(marker.x)),
                @as(i32, @intFromFloat(marker.y)),
                radius,
                core,
            );
            rl.drawCircleLines(
                @as(i32, @intFromFloat(marker.x)),
                @as(i32, @intFromFloat(marker.y)),
                radius + cfg.invader_cell_size * 0.4,
                rim,
            );
            var i: usize = 0;
            while (i < marker.burst_angles.len) : (i += 1) {
                const angle = marker.burst_angles[i];
                const inner = radius * 0.6;
                const outer = radius * 1.6;
                const x0 = marker.x + @cos(angle) * inner;
                const y0 = marker.y + @sin(angle) * inner;
                const x1 = marker.x + @cos(angle) * outer;
                const y1 = marker.y + @sin(angle) * outer;
                rl.drawLine(
                    @as(i32, @intFromFloat(x0)),
                    @as(i32, @intFromFloat(y0)),
                    @as(i32, @intFromFloat(x1)),
                    @as(i32, @intFromFloat(y1)),
                    rim,
                );
            }
            i = 0;
            while (i < marker.debris.len) : (i += 1) {
                const debris_alpha: u8 = @intCast(40 + @as(i32, @intFromFloat(120.0 * pulse)));
                const debris_color = rl.Color{ .r = 255, .g = 220, .b = 120, .a = debris_alpha };
                rl.drawCircle(
                    @as(i32, @intFromFloat(marker.debris[i].x)),
                    @as(i32, @intFromFloat(marker.debris[i].y)),
                    1.2,
                    debris_color,
                );
            }
        }

        if (grenade.active) {
            rl.drawCircle(
                @as(i32, @intFromFloat(grenade.x)),
                @as(i32, @intFromFloat(grenade.y)),
                cfg.grenade_radius,
                rl.Color.yellow,
            );
        }

        if (grenade.explosion_timer > 0) {
            const explosion_radius: f32 = clamp(
                sh * 0.09,
                cfg.grenade_explosion_radius_min,
                cfg.grenade_explosion_radius_max,
            );
            const explosion_color = rl.Color{ .r = 255, .g = 140, .b = 0, .a = 160 };
            rl.drawCircle(
                @as(i32, @intFromFloat(grenade.explosion_x)),
                @as(i32, @intFromFloat(grenade.explosion_y)),
                explosion_radius,
                explosion_color,
            );
            rl.drawCircleLines(
                @as(i32, @intFromFloat(grenade.explosion_x)),
                @as(i32, @intFromFloat(grenade.explosion_y)),
                explosion_radius,
                rl.Color.white,
            );
        }

        const reserve_count: u8 = if (lives_remaining > 0) lives_remaining - 1 else 0;
        var ui_buf: [128]u8 = undefined;
        const grenade_count_s: f32 = @max(0.0, grenade.cooldown);
        const ui_text = if (grenade.cooldown > 0)
            std.fmt.bufPrintZ(
                &ui_buf,
                "Lives: {d}  Reserves: {d}  Level: {d}  GrenCount={d:0.3}s",
                .{ lives_remaining, reserve_count, level, grenade_count_s },
            ) catch "Lives: ?  Reserves: ?  Level: ?  GrenCount=?"
        else
            std.fmt.bufPrintZ(
                &ui_buf,
                "Lives: {d}  Reserves: {d}  Level: {d}  GrenReady",
                .{ lives_remaining, reserve_count, level },
            ) catch "Lives: ?  Reserves: ?  Level: ?  GrenReady";
        rl.drawText(ui_text, 20, 52, 18, rl.Color.white);
        if (grenade.cooldown > 0) {
            const bar_w: i32 = 220;
            const bar_h: i32 = 8;
            const bar_x: i32 = 20;
            const bar_y: i32 = 76;
            const ratio: f32 = clamp01(1.0 - grenade.cooldown / cfg.grenade_cooldown_s);
            rl.drawRectangle(bar_x, bar_y, bar_w, bar_h, rl.Color{ .r = 40, .g = 40, .b = 40, .a = 255 });
            rl.drawRectangle(bar_x, bar_y, @as(i32, @intFromFloat(@as(f32, bar_w) * ratio)), bar_h, rl.Color.yellow);
            rl.drawRectangleLines(bar_x, bar_y, bar_w, bar_h, rl.Color.white);
        }

        if (state != .playing) {
            const overlay = rl.Color{ .r = 0, .g = 0, .b = 0, .a = 170 };
            rl.drawRectangle(0, 0, sw_i, sh_i, overlay);
            const status_y: i32 = @as(i32, @intFromFloat(sh * 0.4));
            if (state == .player_down) {
                rl.drawText("Game over - press Enter to start reserve player", 40, status_y, 22, rl.Color.white);
            } else if (state == .game_over) {
                rl.drawText("All lives lost - press R to restart", 40, status_y, 22, rl.Color.white);
            } else if (state == .level_clear) {
                rl.drawText("Level clear - press N to continue", 40, status_y, 22, rl.Color.white);
            }
        }
    }
}
