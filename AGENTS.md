# Repository Guidelines

## Project Structure & Module Organization
- `src/main.zig` contains the game executable entry point and runtime loop.
- `src/zig_invaders.zig` and `src/root.zig` hold shared module code and tests.
- `build.zig` defines build steps (`run`, `test`) and links the raylib dependency.
- `build.zig.zon` pins external dependencies (raylib-zig) and Zig version.
- `zig-out/` is generated build output; do not edit by hand.

## Build, Test, and Development Commands
- `zig build` builds the executable into `zig-out/bin/zig_invaders`.
- `zig build run` builds and runs the game via the build graph.
- `./run.sh` runs the game with `LIBGL_ALWAYS_SOFTWARE=1` (useful on systems without hardware GL).
- `zig build test` runs both module and executable tests defined in `build.zig`.

## Coding Style & Naming Conventions
- Use Zig’s standard formatting; run `zig fmt` on modified `.zig` files.
- Indentation follows Zig defaults (4 spaces, no tabs).
- Types use UpperCamelCase (`Rectangle`, `GameConfig`).
- Fields and locals use lower_snake_case (`player_speed`, `screen_width`).
- Keep drawing and input logic localized to the main loop for clarity.

## Testing Guidelines
- Tests are Zig `test` blocks using `std.testing`.
- Name tests descriptively, e.g. `test "basic add functionality"`.
- Prefer small, deterministic tests for module functions in `src/root.zig`.

## Commit & Pull Request Guidelines
- Commit messages are short, sentence case, and describe the change directly (e.g., “Player gun + bottom clamp + resize-stable positioning”).
- PRs should include a concise description, relevant screenshots or GIFs for visual changes, and the commands you ran (e.g., `zig build test`).
- Link related issues if applicable.

## Dependencies & Configuration Tips
- Minimum Zig version: 0.15.2 (see `build.zig.zon`).
- raylib is fetched via `build.zig.zon`; run `zig build --fetch` if you need to prefetch dependencies offline.
