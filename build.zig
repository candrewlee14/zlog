const std = @import("std");

pub const pkg = std.build.Pkg{
    .name = "zlog",
    .path = .{ .path = thisDir() ++ "/src/zlog.zig" },
};

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("zlog", "src/zlog.zig");
    lib.setBuildMode(mode);
    lib.install();

    const main_tests = b.addTest("src/zlog.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
