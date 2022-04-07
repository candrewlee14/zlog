const std = @import("std");
const ziglog = @import("ziglog.zig");
var test_allocator = std.testing.allocator;

// Log in JSON format
// pub fn log(
//     comptime level: std.log.Level,
//     comptime scope: @TypeOf(.EnumLiteral),
//     comptime format: []const u8,
//     comptime yeet: []const u8,
//     args: anytype,
// ) void {
//     const scope_prefix = "(" ++ @tagName(scope) ++ "): ";
//     const prefix = yeet ++  
//         switch(level) {
//             .err => "\x1b[31m",
//             .warn => "\x1b[33m",
//             .info => "\x1b[32m",
//             .debug => "\x1b[35m",
//         } ++ levelSmallStr(level) ++ "\x1b[0m " 
//         ++ scope_prefix;

//     // print the message to stderr, silently ignoring any errors
//     std.debug.getStderrMutex().lock();
//     defer std.debug.getStderrMutex().unlock();
//     const stderr = std.io.getStdErr().writer();
//     nosuspend stderr.print(prefix ++ format ++ "\n", args) 
//         catch return;
// }

pub fn main() anyerror!void {
    const writer = std.io.getStdErr().writer();
    const logMan = ziglog.LogManager(.debug, .unixSecs);
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

}

test "logger off" {
    var arr = std.ArrayList(u8).init(test_allocator);
    defer arr.deinit();
    const writer = arr.writer();

    const logMan = ziglog.LogManager(.off, .testMode);
    var logger = logMan.Logger(@TypeOf(writer), .plain, .debug){
        .w = writer, 
        .ctx = "", 
    };
    // This won't be printed
    try logger.print("hey there");
    try std.testing.expect(arr.items.len == 0);
}

test "logger print plain" {
    var arr = std.ArrayList(u8).init(test_allocator);
    defer arr.deinit();
    const writer = arr.writer();

    const logMan = ziglog.LogManager(.debug, .testMode);
    var logger = logMan.Logger(@TypeOf(writer), .plain, .debug){
        .w = writer, 
        .ctx = "", 
    };
    try logger.print("hey there");
    try std.testing.expectEqualStrings("0 DBG message=hey there\n", arr.items);
}

test "logger print json" {
    var arr = std.ArrayList(u8).init(test_allocator);
    defer arr.deinit();
    const writer = arr.writer();

    const logMan = ziglog.LogManager(.debug, .testMode);
    var logger = logMan.Logger(@TypeOf(writer), .json, .debug){
        .w = writer, 
        .ctx = "", 
    };
    try logger.print("hey there");
    const output = 
        \\{"time":0,"level":"debug","message":"hey there"}
        ++ "\n";
    try std.testing.expectEqualStrings(output, arr.items);
}

test "logger event json str" {
    var arr = std.ArrayList(u8).init(test_allocator);
    defer arr.deinit();
    const writer = arr.writer();

    const logMan = ziglog.LogManager(.debug, .testMode);
    var logger = logMan.Logger(@TypeOf(writer), .json, .debug){
        .w = writer, 
        .ctx = "", 
    };
    var event = try logger.withLevel(.debug);
    try event.str("Hey", "This is a field");
    try event.str("Hey2", "This is also a field");
    // Nothing should output because neither msg("blah") nor send() was called
    const output = "";
    try std.testing.expectEqualStrings(output, arr.items);
}

test "logger event json str" {
    var arr = std.ArrayList(u8).init(test_allocator);
    defer arr.deinit();
    const writer = arr.writer();

    const logMan = ziglog.LogManager(.debug, .testMode);
    var logger = logMan.Logger(@TypeOf(writer), .json, .debug){
        .w = writer, 
        .ctx = "", 
    };
    var event = try logger.withLevel(.debug);
    try event.str("Hey", "This is a field");
    try event.str("Hey2", "This is also a field");
    try event.msg("Here's my message");
    const output = 
        \\{"time":0,
        ++
        \\"level":"debug",
        ++
        \\"Hey":"This is a field",
        ++
        \\"Hey2":"This is also a field",
        ++
        \\"message":"Here's my message"}
        ++ "\n";
    try std.testing.expectEqualStrings(output, arr.items);
}

test "logger event json num" {
    var arr = std.ArrayList(u8).init(test_allocator);
    defer arr.deinit();
    const writer = arr.writer();

    const logMan = ziglog.LogManager(.debug, .testMode);
    var logger = logMan.Logger(@TypeOf(writer), .json, .debug){
        .w = writer, 
        .ctx = "", 
    };
    var i : u8 = 100 / 2;
    var event = try logger.withLevel(.debug);
    try event.str("Hey", "This is a field");
    try event.str("Hey2", "This is also a field");
    try event.num("Value1", 10);
    try event.num("Value2", 199.2);
    try event.num("Value3", i);
    try event.msg("Here's my message");
    const output = 
        \\{"time":0,
        ++
        \\"level":"debug",
        ++
        \\"Hey":"This is a field",
        ++
        \\"Hey2":"This is also a field",
        ++
        \\"Value1":10,
        ++
        \\"Value2":199.2,
        ++
        \\"Value3":50,
        ++
        \\"message":"Here's my message"}
        ++ "\n";
    try std.testing.expectEqualStrings(output, arr.items);
}
