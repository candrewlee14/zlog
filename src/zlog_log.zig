const std = @import("std");
const zlog = @import("zlog.zig");

pub const globalLogConf = zlog.LogConfig.default();
pub const globalLogMan = zlog.LogManager(globalLogConf);
pub const globalWriter = std.io.getStdErr().writer();
pub var logger = globalLogMan.Logger(@TypeOf(globalWriter), .json, .debug)
    .new(globalWriter) catch @panic("Failed to create global logger");
