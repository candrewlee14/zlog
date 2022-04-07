const std = @import("std");
const zlog = @import("zlog.zig");

pub fn main() anyerror!void {
    const writer = std.io.getStdErr().writer();
    const conf = comptime zlog.LogConfig.default();
    const logMan = zlog.LogManager(conf);
    var logger = logMan.Logger(@TypeOf(writer), .json, .debug){
        .w = writer, 
        .ctx = "", 
    };
    try logger.print("hey there");

    var logger2 = logMan.Logger(@TypeOf(writer), .pretty, .debug){
        .w = writer, 
        .ctx = "", 
    };
    try logger2.print("hey there");
    try logger2.level(.warn)
        .print("look, a warning!");

    var event = try logger2.withLevel(.err);
    try event.str("Hey2", "This is also a field");
    try event.num("Value1", 10);
    try event.msgf("This is using msgf to append a {s} here and {d} here", 
        .{"string", 10.3});
}
