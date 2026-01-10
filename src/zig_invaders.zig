const std = @import("std");

pub const grenade_slots: u8 = 9;
pub const grenade_max_kills: u8 = 3;
pub const grenade_mask_all: u16 = (@as(u16, 1) << grenade_slots) - 1;

pub fn bufferedPrint() void {
    std.debug.print("zig_invaders module online.\n", .{});
}

fn selectKillsFromMask(occupied_mask: u16, kills_target: u8, rng: *std.Random) u16 {
    var indices: [grenade_slots]u8 = undefined;
    var count: u8 = 0;
    var idx: u8 = 0;
    while (idx < grenade_slots) : (idx += 1) {
        const bit: u16 = @as(u16, 1) << @as(u4, @intCast(idx));
        if ((occupied_mask & bit) != 0) {
            indices[count] = idx;
            count += 1;
        }
    }

    const kills = @min(kills_target, count);
    var kill_mask: u16 = 0;
    var i: u8 = 0;
    while (i < kills) : (i += 1) {
        const pick: u8 = rng.intRangeLessThan(u8, i, count);
        const swap = indices[i];
        indices[i] = indices[pick];
        indices[pick] = swap;
        kill_mask |= @as(u16, 1) << @as(u4, @intCast(indices[i]));
    }

    return kill_mask & grenade_mask_all;
}

pub fn grenadeKillMask(occupied_mask: u16, rng: *std.Random) u16 {
    const masked_occupied = occupied_mask & grenade_mask_all;
    const occupied_count: u8 = @intCast(@popCount(masked_occupied));

    if (occupied_count == 0) return 0;
    if (occupied_count >= grenade_slots) {
        return selectKillsFromMask(masked_occupied, grenade_max_kills, rng);
    }

    const ratio: f32 = @as(f32, @floatFromInt(occupied_count)) / @as(f32, grenade_slots);
    const w1: f32 = 1.0;
    const w2: f32 = ratio * ratio;
    const w3: f32 = ratio * ratio * ratio * ratio;
    const total: f32 = w1 + w2 + w3;
    const roll: f32 = rng.float(f32) * total;
    var kills_target: u8 = 1;

    if (roll < w3) {
        kills_target = 3;
    } else if (roll < w3 + w2) {
        kills_target = 2;
    } else {
        kills_target = 1;
    }

    return selectKillsFromMask(masked_occupied, @min(kills_target, grenade_max_kills), rng);
}

pub fn grenadeApplyKills(occupied_mask: u16, kill_mask: u16) struct { killed_mask: u16, remaining_mask: u16 } {
    const masked_occupied = occupied_mask & grenade_mask_all;
    const masked_kill = kill_mask & grenade_mask_all;
    const killed = masked_occupied & masked_kill;

    return .{
        .killed_mask = killed,
        .remaining_mask = masked_occupied & ~killed,
    };
}

test "grenade kill mask caps at one third of 9 slots" {
    var prng = std.Random.DefaultPrng.init(0x8b7c_42d1);
    var rng = prng.random();
    const occupied_mask: u16 = grenade_mask_all;

    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const kill_mask = grenadeKillMask(occupied_mask, &rng);
        const killed_count: u16 = @popCount(kill_mask);
        try std.testing.expect(killed_count <= grenade_max_kills);
    }
}

test "grenade kill mask stays within the nine-slot grid" {
    var prng = std.Random.DefaultPrng.init(0x1422_9871);
    var rng = prng.random();
    const occupied_mask: u16 = grenade_mask_all;

    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const kill_mask = grenadeKillMask(occupied_mask, &rng);
        try std.testing.expect((kill_mask & ~grenade_mask_all) == 0);
    }
}

test "grenade kill mask returns exactly three when full" {
    var prng = std.Random.DefaultPrng.init(0x2334_5a5b);
    var rng = prng.random();
    const occupied_mask: u16 = grenade_mask_all;

    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const kill_mask = grenadeKillMask(occupied_mask, &rng);
        try std.testing.expect(@popCount(kill_mask) == grenade_max_kills);
    }
}

test "grenade kill mask respects sparse occupancy" {
    var prng = std.Random.DefaultPrng.init(0x3f92_11aa);
    var rng = prng.random();
    const occupied_mask: u16 = 0b000_001_011;

    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const kill_mask = grenadeKillMask(occupied_mask, &rng);
        try std.testing.expect((kill_mask & ~occupied_mask) == 0);
        try std.testing.expect(@popCount(kill_mask) <= @popCount(occupied_mask));
    }
}

test "grenade apply kills respects occupancy mask" {
    const occupied: u16 = 0b101_001_001;
    const kill_mask: u16 = 0b001_011_000;
    const result = grenadeApplyKills(occupied, kill_mask);

    try std.testing.expect(result.killed_mask == (occupied & kill_mask));
    try std.testing.expect(result.remaining_mask == (occupied & ~kill_mask) & grenade_mask_all);
}
