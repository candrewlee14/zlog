const std = @import("std");
const zlog = @import("zlog.zig");
const log = @import("zlog_log.zig");

pub fn main() anyerror!void {
    var logger2 = try log.globalLogMan.Logger(@TypeOf(log.globalWriter), .pretty, .debug)
        .new(log.globalWriter);
    try logger2.print("hey there");
    var sublogger = try logger2.level(.warn);
    try sublogger.print("look, a warning!");

    var event = try logger2.withLevel(.err);
    try event.str("Hey2", "This is also a field");
    try event.num("Value1", 10);
    try event.msgf("This is using msgf to append a {s} here and {d} here", 
        .{"string", 10.3});
}
