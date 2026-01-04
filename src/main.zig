onst rl = @import("raylib");

pub fn main() !void {
    rl.initWindow(800, 450, "zig-invaders");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    var frame: i32 = 0;

    while (!rl.windowShouldClose()) {
        frame += 1;

        rl.beginDrawing();

        // Brutal visibility: magenta background + huge white text.
        rl.clearBackground(rl.Color{ .r = 255, .g = 0, .b = 255, .a = 255 });

        rl.drawText("IF YOU SEE THIS, DRAWING WORKS", 40, 40, 24, rl.Color{ .r = 255, .g = 255, .b = 255, .a = 255 });

        // Draw a moving rectangle so you can’t miss frame updates.
        const x: i32 = @mod(frame * 5, 800);
        rl.drawRectangle(x, 200, 80, 60, rl.Color{ .r = 255, .g = 255, .b = 0, .a = 255 });

        rl.endDrawing();
    }
}
