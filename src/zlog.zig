const std = @import("std");
const builtin = @import("builtin");
const tc = @import("termcolor.zig");
const test_allocator = std.testing.allocator;

pub const TimeFormat = enum {
    unixSecs,
    testMode,
};

pub const LevelType = enum {
    off,
    panic,
    fatal,
    err,
    warn,
    info,
    debug,
    trace,
    pub fn asText(self: LevelType) []const u8 {
        return switch (self) {
            .off => "off",
            .panic => "panic",
            .fatal => "fatal",
            .err => "err",
            .warn => "warn",
            .info => "info",
            .debug => "debug",
            .trace => "trace"
        };
    }
    /// The default log level is based on build mode.
    pub const default: LevelType = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe => .info,
        .ReleaseFast, .ReleaseSmall => .err,
    };
};

// A wrapper around std.BoundedArray with an added writer interface
pub fn BoundedStr(comptime bufSize: usize) type {
    return struct {
        const Self = @This();
        data: std.BoundedArray(u8, bufSize),

        const Writer = std.io.Writer(
            *Self,
            error{EndOfBuffer},
            appendWrite,
        );
        pub fn init() !Self {
            return Self{
                .data = try std.BoundedArray(u8, bufSize).init(0),
            };
        }
        fn appendWrite(self: *Self, str: []const u8) error{EndOfBuffer}!usize {
             self.data.appendSlice(str) catch return error.EndOfBuffer;
             return str.len;
        }
        fn writer(self: *Self) Writer {
            return .{ .context = self };
        }
    };
}

pub const LogConfig = struct {
    globalLogLevel: LevelType,
    timeFormat: TimeFormat,
    eventBufSize: usize,

    const Self = @This();
    pub fn default() Self {
        return Self{
            .globalLogLevel = LevelType.default,
            .timeFormat =  .unixSecs,
            .eventBufSize =  1000,
        };
    }
    pub fn off() Self {
        return Self{
            .globalLogLevel = .off,
            .timeFormat =  .unixSecs,
            .eventBufSize =  1000,
        };
    }
    pub fn testMode() Self {
        return Self{
            .globalLogLevel = LevelType.default,
            .timeFormat =  .testMode,
            .eventBufSize =  1000,
        };
    }
};

pub fn LogManager(
    comptime conf: LogConfig,
) type {
    return struct {
        fn getTime() i128 {
            return switch (conf.timeFormat) {
                .unixSecs => std.time.timestamp(),
                .testMode => 0,
            };
        }

        pub fn Event(
            comptime writerType: type,
            comptime fmtMode: FormatMode,
            comptime logLevel: LevelType,
        ) type {
            return struct {
                w: writerType,
                buf: BoundedStr(conf.eventBufSize),
                timeVal: i128,

                const Self = @This();
                // Creates new Event with current time
                fn new(writer: writerType) !Self {
                    const timeVal = getTime();
                    var newEvent = Self{
                        .w = writer,
                        .timeVal = timeVal,
                        .buf = try BoundedStr(conf.eventBufSize).init(),
                    };
                    comptime if (@enumToInt(logLevel) > @enumToInt(conf.globalLogLevel)){
                        return newEvent;
                    };
                    const w = newEvent.buf.writer();
                    switch (fmtMode) { 
                        .json => {
                            try w.writeAll("{");
                            try w.print("\"time\":{}", .{timeVal});
                            try w.writeAll(
                               ",\"level\":\"" ++ logLevel.asText() ++ "\"",
                            );
                        },
                        .pretty => {
                            try w.print(tc.Gray ++ "{} " ++ tc.Reset, .{timeVal});
                            const lvlStr = switch(logLevel) {
                                .panic, .fatal, .err => tc.Red,
                                .warn => tc.Yellow,
                                .info => tc.Green,
                                .debug => tc.Magenta,
                                .trace => tc.Cyan,
                                else => "",
                            } ++ levelSmallStr(logLevel) ++ tc.Reset;
                            try w.writeAll(lvlStr);
                        },
                        .plain => {
                            try w.print("{} ", .{timeVal});
                            try w.writeAll(levelSmallStr(logLevel));
                        },
                    }
                    return newEvent;
                }

                /// Add a key:value pair to this event
                /// isNum will remove the quotes around JSON in the case of a num
                fn add(
                    self: *Self, 
                    key: []const u8, 
                    comptime valFmtStr: []const u8, 
                    comptime isNum: bool,
                    args: anytype
                ) !void {
                    comptime if (@enumToInt(logLevel) > @enumToInt(conf.globalLogLevel)){
                        return;
                    };
                    const w = self.buf.writer();
                    // const w = self.w;
                    switch (fmtMode) {
                        .json => {
                            try w.print(",\"{s}\":", .{key});
                            if (!isNum) { try w.writeAll("\""); }
                            try w.print(valFmtStr, args);
                            if (!isNum) { try w.writeAll("\""); }
                        },
                        .plain => {
                            try w.print(" {s}=", .{key});
                            try w.print(valFmtStr, args);
                        },
                        .pretty => {
                            try w.print(tc.Gray ++ " {s}=" ++ tc.Reset, .{key});
                            try w.print(valFmtStr, args);
                        },
                    }
                }
                pub fn str(self: *Self, key: []const u8, val: []const u8) !void {
                    try self.add(key, "{s}", false, .{val});
                }
                pub fn num(self: *Self, key: []const u8, val: anytype) !void {
                    const valTinfo = @typeInfo(@TypeOf(val));
                    switch (comptime valTinfo) {
                        .Int, .Float, .ComptimeInt, .ComptimeFloat => 
                            try self.add(key, "{d}", true, .{val}),
                        else => @compileError(
                            "Expected int or float value, instead got " 
                            ++ @typeName(@TypeOf(val))),
                    }
                }
                /// Send this event to the writer with no message.
                /// The event should then be discarded.
                pub fn send(self: *Self) !void {
                    comptime if (@enumToInt(logLevel) > @enumToInt(conf.globalLogLevel)){
                        return;
                    };
                    try self.w.writeAll(self.buf.data.constSlice());
                    switch (fmtMode) {
                        .json => {
                            try self.w.writeAll("}\n");
                        },
                        .plain, .pretty => {
                            try self.w.writeAll("\n");
                        },
                    }
                }
                /// Send this event to the writer with the given message.
                pub fn msg(self: *Self, msgStr: []const u8) !void {
                    try self.str("message", msgStr);
                    try self.send();
                }
                pub fn msgf(self: *Self, 
                    comptime fmtStr: []const u8, 
                    args: anytype
                ) !void {
                    try self.add("message", fmtStr, false, args);
                    try self.send();
                }
            };
        }

        fn levelSmallStr(lvl: LevelType) []const u8 {
            return switch(lvl) {
                .off => "OFF",
                .panic => "PAN",
                .fatal => "FTL",
                .err => "ERR",
                .warn => "WRN",
                .info => "INF",
                .debug => "DBG",
                .trace => "TRC",
            };
        }

        pub const FormatMode = enum {
            json,
            pretty,
            plain,
        };

        pub fn Logger(
            comptime writerType: type, 
            comptime fmtMode: FormatMode,
            comptime logLevel: LevelType,
        ) type {
            return struct {
                w: writerType,
                ctx: []const u8,

                const Self = @This();
                pub fn getLevel() LevelType {
                    return logLevel;
                }
                pub fn level(
                    self: *Self, 
                    comptime lvl: LevelType,
                ) Logger(writerType, fmtMode, lvl) {
                    return Logger(writerType, fmtMode, lvl){
                        .w = self.w,
                        .ctx = self.ctx,
                    };
                }
                pub fn withLevel(
                    self: *Self, 
                    comptime lvl: LevelType
                ) !Event(writerType, fmtMode, lvl) {
                    return Event(writerType, fmtMode, lvl).new(self.w);
                }
                pub fn print(self: *Self, msg: []const u8) !void {
                    comptime if (@enumToInt(logLevel) > @enumToInt(conf.globalLogLevel)){
                        return;
                    };
                    var event = try self.withLevel(logLevel);
                    try event.msg(msg);
                }
            };
        }
    };
}

// --- TESTING --- 

test "logger off" {
    var arr = std.ArrayList(u8).init(test_allocator);
    defer arr.deinit();
    const writer = arr.writer();

    const conf = comptime LogConfig.off();
    const logMan = LogManager(conf);
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

    const conf = comptime LogConfig.testMode();
    const logMan = LogManager(conf);
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

    const conf = comptime LogConfig.testMode();
    const logMan = LogManager(conf);
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

    const conf = comptime LogConfig.testMode();
    const logMan = LogManager(conf);
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

    const conf = comptime LogConfig.testMode();
    const logMan = LogManager(conf);
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
    const conf = comptime LogConfig.testMode();
    const logMan = LogManager(conf);
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
