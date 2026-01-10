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
    var player_dead = false;

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

        // Detect resize / monitor move; reapply relative X
        if (sw_i != prev_sw or sh_i != prev_sh) {
            prev_sw = sw_i;
            prev_sh = sh_i;

            const max_x: f32 = sw - player.width;
            player.x = clamp(player_rel_x * max_x, 0, max_x);
        }

        // Input
        var dx: f32 = 0;
        if (!player_dead) {
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
        if (max_x > 0) {
            player_rel_x = clamp01(player.x / max_x);
        } else {
            player_rel_x = 0.0;
        }

        // Bottom safety margin scales with screen height (different monitors/taskbars)
        const safe_bottom: f32 = @max(24.0, @min(96.0, sh * 0.06)); // 6% height, clamped
        baseline_y = sh - player.height - safe_bottom;
        if (!baseline_set) {
            player.y = baseline_y;
            baseline_set = true;
        } else if (player.y > baseline_y) {
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

        if (invader_origin_x <= 16 or invader_origin_x + invader_group_width >= sw - 16) {
            invader_dir *= -1.0;
            invader_offset_y += cfg.invader_drop * invader_speed_scale;
            invader_origin_x = (sw - invader_group_width) * 0.5 + invader_offset_x;
            invader_origin_y = sh * 0.12 + invader_offset_y;
        }
        invader_offset_x += invader_dir * cfg.invader_speed * invader_speed_scale * dt;

        if (invader_fire_timer > 0) {
            invader_fire_timer = @max(0, invader_fire_timer - dt);
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

        if (!player_dead) {
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

        const can_fire = !player_dead and ((!overlaps_base) or (barrel_protrudes and shoulders_exposed));
        if (can_fire and rl.isKeyPressed(.space)) {
            for (&bullets) |*bullet| {
                if (!bullet.active) {
                    bullet.active = true;
                    bullet.x = player_center_x;
                    bullet.y = barrel_y;
                    bullet.vx = player_vel_x * cfg.bullet_inherit_vx;
                    bullet.vy = -cfg.bullet_speed;
                    break;
                }
            }
        }

        if (!player_dead and !overlaps_base and rl.isKeyPressed(.g) and !grenade.active and grenade.explosion_timer <= 0 and grenade.cooldown <= 0) {
            grenade.active = true;
            grenade.flight_time = 0;
            grenade.x = player_center_x;
            grenade.y = barrel_y;
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
            if (@abs(player_vel_x) >= cfg.grenade_arc_speed_threshold) {
                const angle: f32 = cfg.grenade_arc_max_deg * (@as(f32, std.math.pi) / 180.0);
                const max_ratio: f32 = std.math.tan(angle);
                const sign: f32 = if (player_vel_x < 0) -1.0 else 1.0;
                grenade.vx = max_ratio * @abs(grenade.vy) * sign;
                grenade.vx += player_vel_x * cfg.grenade_inherit_vx;
            }
        }

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
            var has_alive = false;
            for (invaders) |row| {
                for (row) |invader| {
                    if (invader.alive) {
                        has_alive = true;
                        break;
                    }
                }
                if (has_alive) break;
            }

            if (has_alive) {
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
                    var alive_count: usize = 0;
                    var row_idx: usize = 0;
                    while (row_idx < InvaderGridRows) : (row_idx += 1) {
                        var col_idx: usize = 0;
                        while (col_idx < InvaderGridCols) : (col_idx += 1) {
                            if (invaders[row_idx][col_idx].alive) {
                                alive_indices[alive_count] = row_idx * InvaderGridCols + col_idx;
                                alive_count += 1;
                            }
                        }
                    }
                    if (alive_count > 0) {
                        const pick = rng.intRangeLessThan(usize, 0, alive_count);
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

            if (shot.active and !player_dead) {
                const wobble = if (shot.squiggly) std.math.sin(shot.age * 14.0) * 3.0 else 0.0;
                const shot_x = shot.x + wobble;
                if (shot_x >= player.x and shot_x <= player.x + player.width and shot.y >= player.y and shot.y <= player.y + player.height) {
                    shot.active = false;
                    if (squiggly_death_pending) {
                        player_dead = true;
                    } else {
                        player_hit_streak += 1;
                        if (player_hit_streak >= 4) {
                            player_dead = true;
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
            grenade.x += grenade.vx * dt;
            grenade.y += grenade.vy * dt;

            if (grenade.y >= ground_y or grenade.flight_time >= cfg.grenade_fuse_s) {
                grenade.active = false;
                grenade.explosion_timer = cfg.grenade_explosion_s;
                grenade.explosion_x = grenade.x;
                grenade.explosion_y = @min(grenade.y, ground_y);
                grenade.cooldown = cfg.grenade_cooldown_s;
                var lowest_row: i32 = -1;
                var lowest_col: i32 = -1;
                var row_idx: i32 = @as(i32, InvaderGridRows) - 1;
                while (row_idx >= 0) : (row_idx -= 1) {
                    var found_in_row = false;
                    var col_idx: i32 = 0;
                    while (col_idx < @as(i32, InvaderGridCols)) : (col_idx += 1) {
                        if (invaders[@intCast(row_idx)][@intCast(col_idx)].alive) {
                            lowest_row = row_idx;
                            found_in_row = true;
                            break;
                        }
                    }
                    if (found_in_row) break;
                }

                if (lowest_row >= 0) {
                    var best_dist: f32 = 1e9;
                    var col_idx: i32 = 0;
                    while (col_idx < @as(i32, InvaderGridCols)) : (col_idx += 1) {
                        if (!invaders[@intCast(lowest_row)][@intCast(col_idx)].alive) continue;
                        const inv_x = invader_origin_x + @as(f32, @floatFromInt(col_idx)) * invader_step_x + invader_width * 0.5;
                        const dist = @abs(inv_x - grenade.explosion_x);
                        if (dist < best_dist) {
                            best_dist = dist;
                            lowest_col = col_idx;
                        }
                    }
                }

                if (lowest_row >= 0 and lowest_col >= 0) {
                    var use_three_by_three = false;
                    if (lowest_row >= 2) {
                        var check_row: i32 = lowest_row - 1;
                        while (check_row >= lowest_row - 2) : (check_row -= 1) {
                            var col_idx: i32 = lowest_col - 2;
                            while (col_idx <= lowest_col + 2) : (col_idx += 1) {
                                if (col_idx < 0 or col_idx >= @as(i32, InvaderGridCols)) continue;
                                if (invaders[@intCast(check_row)][@intCast(col_idx)].alive) {
                                    use_three_by_three = true;
                                    break;
                                }
                            }
                            if (use_three_by_three) break;
                        }
                    }

                    const grid_cols: i32 = if (use_three_by_three) 3 else 2;
                    const grid_rows: i32 = if (use_three_by_three) 3 else 2;
                    var row_start: i32 = if (use_three_by_three) lowest_row - 2 else lowest_row - 1;
                    if (row_start < 0) row_start = 0;
                    var col_start: i32 = lowest_col - 1;
                    if (col_start < 0) col_start = 0;
                    const max_col_start = @as(i32, InvaderGridCols) - grid_cols;
                    if (col_start > max_col_start) col_start = max_col_start;

                    const grid_size: usize = @intCast(grid_cols * grid_rows);
                    var positions: [9]u8 = undefined;
                    var i: usize = 0;
                    while (i < grid_size) : (i += 1) {
                        positions[i] = @intCast(i);
                    }

                    var rng = prng.random();
                    var pick_count: usize = 3;
                    if (grid_size < pick_count) pick_count = grid_size;
                    var idx: usize = 0;
                    while (idx < pick_count) : (idx += 1) {
                        const pick = rng.intRangeLessThan(usize, idx, grid_size);
                        const swap = positions[idx];
                        positions[idx] = positions[pick];
                        positions[pick] = swap;
                    }

                    var killed_any = false;
                    idx = 0;
                    while (idx < pick_count) : (idx += 1) {
                        const pos = positions[idx];
                        const grid_cols_usize: usize = @intCast(grid_cols);
                        const r = row_start + @as(i32, @intCast(pos / grid_cols_usize));
                        const c = col_start + @as(i32, @intCast(pos % grid_cols_usize));
                        if (r < 0 or r >= @as(i32, InvaderGridRows) or c < 0 or c >= @as(i32, InvaderGridCols)) continue;

                        const marker_x = invader_origin_x + @as(f32, @floatFromInt(c)) * invader_step_x + invader_width * 0.5;
                        const marker_y = invader_origin_y + @as(f32, @floatFromInt(r)) * invader_step_y + invader_height * 0.5;
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

                        if (invaders[@intCast(r)][@intCast(c)].alive) {
                            invaders[@intCast(r)][@intCast(c)].alive = false;
                            killed_any = true;
                        }
                    }

                    if (killed_any) {
                        invader_speed_scale *= 1.0033;
                    }
                }
            }
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);
        rl.drawText("Zig Invaders", 20, 20, 24, rl.Color.white);

        // Player body
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
    }
}
