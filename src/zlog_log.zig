const std = @import("std");
const zlog = @import("zlog.zig");

pub const logConf = zlog.LogConfig.default();
pub const logMan = zlog.LogManager(logConf);
pub const writer = std.io.getStdErr().writer();
pub const fmtMode = .json;
pub const loggerDefaultLevel = .debug;
pub var logger = logMan.Logger(@TypeOf(writer), fmtMode, loggerDefaultLevel)
    .new(writer) catch @panic("Failed to create global logger");

/// Return current logger log level
pub fn getLevel() zlog.LevelType {
    return logger.getLevel();
}
/// Returns a sublogger at the given log level
pub fn level( comptime lvl: zlog.LevelType,) !zlog.Logger(@TypeOf(writer), fmtMode, loggerDefaultLevel) {
    return logger.level(lvl);
}
/// Add key:boolean context to this logger
pub fn booleanCtx(key: []const u8, val: bool) !void {
    try logger.booleanCtx(key, val);
}
/// Add key:num context to this logger
pub fn numCtx(key: []const u8, val: anytype) !void {
    try logger.numCtx(key, val);
}
/// Add key:string context to this logger
pub fn strCtx(key: []const u8, val: []const u8) !void {
    try logger.strCtx(key, val);
}
/// Returns an event that at the given log level 
pub fn withLevel( comptime lvl: zlog.LevelType) !zlog.Event(@TypeOf(writer), fmtMode, loggerDefaultLevel) {
    return logger.withLevel(lvl);
}
/// Log a message at this logger's level
pub fn print(msg: []const u8) !void {
    try logger.print(msg);
}
