const std = @import("std");
const zlog = @import("zlog.zig");
const logger = &@import("zlog_log.zig").logger;

pub fn main() anyerror!void {
    try logger.print("hey there");
    var sublogger = try logger.level(.warn);
    try sublogger.print("look, a warning!");

    var event = try logger.withLevel(.err);
    try event.str("Hey2", "This is also a field");
    try event.num("Value1", 10);
    try event.msgf("This is using msgf to append a {s} here and {d} here", 
        .{"string", 10.3});
}
