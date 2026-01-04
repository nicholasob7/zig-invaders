#!/usr/bin/env bash
export LIBGL_ALWAYS_SOFTWARE=1
exec zig build run
