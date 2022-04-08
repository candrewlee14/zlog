const std = @import("std");
const builtin = @import("builtin");
const test_allocator = std.testing.allocator;

// Global logger setup
const globalLogConf = LogConfig.default();
const globalLogMan = LogManager(globalLogConf);
const globalWriter = std.io.getStdErr().writer();
const loggerDefaultLevel = .debug;

pub var globalJsonLogger = globalLogMan.Logger(@TypeOf(globalWriter), .json, loggerDefaultLevel)
    .new(globalWriter) catch @panic("Failed to create global JSON logger");
pub var globalPrettyLogger = globalLogMan.Logger(@TypeOf(globalWriter), .pretty, loggerDefaultLevel)
    .new(globalWriter) catch @panic("Failed to create global pretty logger");
pub var globalPlainLogger = globalLogMan.Logger(@TypeOf(globalWriter), .plain, loggerDefaultLevel)
    .new(globalWriter) catch @panic("Failed to create global plain logger");

/// Term Colors
pub const tc = struct {
    pub const Red = "\x1b[31m";
    pub const Yellow = "\x1b[33m";
    pub const Green = "\x1b[32m";
    pub const Gray = "\x1b[90m";
    pub const Blue = "\x1b[34m";
    pub const Magenta = "\x1b[35m";
    pub const Cyan = "\x1b[36m";
    pub const White = "\x1b[37m";
    pub const Reset = "\x1b[0m";
};

/// Format for writing the time.
/// .unixSecs - example: 1680183
/// .testMode - always 0
pub const TimeFormat = enum {
    unixSecs,
    testMode,
};

/// Mode for log formats.
/// .pretty - good for console applications
/// .plain - pretty with no color
/// .json - good for log storage & querying
pub const FormatMode = enum {
    json,
    pretty,
    plain,
};

/// Log level.
/// Example: choosing .debug as the global log level will filter out .trace logs and show the rest
pub const LevelType = enum {
    off,
    panic,
    fatal,
    err,
    warn,
    info,
    debug,
    trace,
    /// Get log level in full text form
    pub fn asText(self: LevelType) []const u8 {
        return switch (self) {
            .off => "off",
            .panic => "panic",
            .fatal => "fatal",
            .err => "err",
            .warn => "warn",
            .info => "info",
            .debug => "debug",
            .trace => "trace",
        };
    }
    /// Short string for pretty printing the log level
    fn as3Char(self: LevelType) []const u8 {
        return switch (self) {
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
    /// The default log level is based on build mode.
    pub const default: LevelType = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe => .info,
        .ReleaseFast, .ReleaseSmall => .warn,
    };
};

/// A wrapper around std.BoundedArray with an added writer interface
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
        /// Get writer for BoundedStr
        fn writer(self: *Self) Writer {
            return .{ .context = self };
        }
    };
}

/// Log Config type.
/// Passed into LogManager function.
pub const LogConfig = struct {
    logLevelFilter: LevelType,
    timeFormat: TimeFormat,
    eventBufSize: usize,

    const Self = @This();
    /// Default log config
    pub fn default() Self {
        return Self{
            .logLevelFilter = LevelType.default,
            .timeFormat = .unixSecs,
            .eventBufSize = 1000,
        };
    }
    /// Global log level is off, so nothing should be logged
    pub fn off() Self {
        return Self{
            .logLevelFilter = .off,
            .timeFormat = .unixSecs,
            .eventBufSize = 1000,
        };
    }
    /// Test mode where time values are all 0 
    pub fn testMode() Self {
        return Self{
            .logLevelFilter = LevelType.default,
            .timeFormat = .testMode,
            .eventBufSize = 1000,
        };
    }
};

/// Log Manager will take in a comptime LogConfig.
/// A program should need only one Log Manager which creates Loggers
pub fn LogManager(
    comptime conf: LogConfig,
) type {
    return struct {
        /// Get current time depending on the LogConfig's timeFormat.
        fn getTime() i128 {
            return switch (conf.timeFormat) {
                .unixSecs => std.time.timestamp(),
                .testMode => 0,
            };
        }

        /// Events write the logs.
        /// Add fields to the event, then send the log with send(), msg("foo"), or msgf("foo", .{}).
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
                /// Creates new Event with current time
                fn new(writer: writerType) !Self {
                    var newEvent = Self{
                        .w = writer,
                        .timeVal = undefined,
                        .buf = undefined,
                    };
                    // Filter out lower log levels
                    comptime if (@enumToInt(logLevel) > @enumToInt(conf.logLevelFilter) or (logLevel == .off)) {
                        return newEvent;
                    };
                    const timeVal = getTime();
                    newEvent.timeVal = timeVal;
                    newEvent.buf = try BoundedStr(conf.eventBufSize).init();
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
                            const lvlStr = switch (logLevel) {
                                .panic, .fatal, .err => tc.Red,
                                .warn => tc.Yellow,
                                .info => tc.Green,
                                .debug => tc.Magenta,
                                .trace => tc.Cyan,
                                else => "",
                            } ++ logLevel.as3Char() ++ tc.Reset;
                            try w.writeAll(lvlStr);
                        },
                        .plain => {
                            try w.print("{} ", .{timeVal});
                            try w.writeAll(logLevel.as3Char());
                        },
                    }
                    return newEvent;
                }

                /// Add a key:value pair to this event
                /// noQuotes will remove the quotes around JSON in the case of a num/bool
                /// NOTE: must use msg, msgf, or send methods to dispatch log
                pub fn add(self: *Self, key: []const u8, comptime valFmtStr: []const u8, comptime noQuotes: bool, args: anytype) !void {
                    // Filter out lower log levels
                    comptime if (@enumToInt(logLevel) > @enumToInt(conf.logLevelFilter) or (logLevel == .off)) {
                        return;
                    };
                    const w = self.buf.writer();
                    // const w = self.w;
                    switch (fmtMode) {
                        .json => {
                            try w.print(",\"{s}\":", .{key});
                            if (!noQuotes) {
                                try w.writeAll("\"");
                            }
                            try w.print(valFmtStr, args);
                            if (!noQuotes) {
                                try w.writeAll("\"");
                            }
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
                /// Add key:str pair to ev.
                /// NOTE: must use msg, msgf, or send methods to dispatch log
                pub fn str(self: *Self, key: []const u8, val: []const u8) !void {
                    try self.add(key, "{s}", false, .{val});
                }
                /// Add key:str pair to event using format string with value struct.
                /// NOTE: must use msg, msgf, or send methods to dispatch log
                pub fn strf(self: *Self, key: []const u8, comptime fmtStr: []const u8, val: anytype) !void {
                    try self.add(key, fmtStr, false, val);
                }
                /// Add key:num pair to ev.
                /// NOTE: must use msg, msgf, or send methods to dispatch log
                pub fn num(self: *Self, key: []const u8, val: anytype) !void {
                    const valTinfo = @typeInfo(@TypeOf(val));
                    switch (comptime valTinfo) {
                        .Int, .Float, .ComptimeInt, .ComptimeFloat => try self.add(key, "{d}", true, .{val}),
                        else => @compileError("Expected int or float value, instead got " ++ @typeName(@TypeOf(val))),
                    }
                }
                /// Add key:boolean pair to event
                /// NOTE: must use msg, msgf, or send methods to dispatch log
                pub fn boolean(self: *Self, key: []const u8, val: anytype) !void {
                    const valTinfo = @typeInfo(@TypeOf(val));
                    switch (comptime valTinfo) {
                        .Bool => try self.add(key, "{d}", true, .{val}),
                        else => @compileError("Expected bool value, instead got " ++ @typeName(@TypeOf(val))),
                    }
                }
                /// Send this event to the writer with no message.
                /// The event should then be discarded.
                pub fn send(self: *Self) !void {
                    // Filter out lower log levels
                    comptime if (@enumToInt(logLevel) > @enumToInt(conf.logLevelFilter) or (logLevel == .off)) {
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
                /// The event should then be discarded.
                pub fn msg(self: *Self, msgStr: []const u8) !void {
                    try self.str("message", msgStr);
                    try self.send();
                }
                /// Send this event to the writer with a message from 
                /// a format string and args struct.
                /// The event should then be discarded.
                pub fn msgf(self: *Self, comptime fmtStr: []const u8, args: anytype) !void {
                    try self.strf("message", fmtStr, args);
                    try self.send();
                }
            };
        }


        /// Loggers hold a context, and they create log Events to write logs
        pub fn Logger(
            comptime writerType: type,
            comptime fmtMode: FormatMode,
            comptime logLevel: LevelType,
        ) type {
            return struct {
                w: writerType,
                ctx: BoundedStr(conf.eventBufSize),

                const Self = @This();
                /// Create new logger
                pub fn new(w: writerType) !Self {
                    return Self{
                        .w = w,
                        .ctx = try BoundedStr(conf.eventBufSize).init(),
                    };
                }
                /// Return current logger log level
                pub fn getLevel() LevelType {
                    return logLevel;
                }
                /// Returns a sublogger at the given log level
                pub fn sublogger(
                    self: *Self,
                    comptime lvl: LevelType,
                ) !Logger(writerType, fmtMode, lvl) {
                    var newCtx = try BoundedStr(conf.eventBufSize).init();
                    try newCtx.writer().writeAll(self.ctx.data.constSlice());
                    return Logger(writerType, fmtMode, lvl){
                        .w = self.w,
                        .ctx = newCtx,
                    };
                }
                /// Add a key:value pair context to this logger
                /// noQuotes will remove the quotes around JSON in the case of a num/bool
                /// NOTE: must use msg, msgf, or send methods to dispatch log
                fn addCtx(self: *Self, key: []const u8, comptime valFmtStr: []const u8, comptime noQuotes: bool, args: anytype) !void {
                    // Filter out lower log levels
                    comptime if (@enumToInt(logLevel) > @enumToInt(conf.logLevelFilter) or (logLevel == .off)) {
                        return;
                    };
                    const w = self.ctx.writer();
                    switch (fmtMode) {
                        .json => {
                            try w.print(",\"{s}\":", .{key});
                            if (!noQuotes) {
                                try w.writeAll("\"");
                            }
                            try w.print(valFmtStr, args);
                            if (!noQuotes) {
                                try w.writeAll("\"");
                            }
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
                /// Add key:boolean context to this logger
                pub fn booleanCtx(self: *Self, key: []const u8, val: bool) !void {
                    try self.addCtx(key, "{}", true, .{val});
                }
                /// Add key:num context to this logger
                pub fn numCtx(self: *Self, key: []const u8, val: anytype) !void {
                    const valTinfo = @typeInfo(@TypeOf(val));
                    switch (comptime valTinfo) {
                        .Int, .Float, .ComptimeInt, .ComptimeFloat => try self.addCtx(key, "{d}", true, .{val}),
                        else => @compileError("Expected int or float value, instead got " ++ @typeName(@TypeOf(val))),
                    }
                }
                /// Add key:string context to this logger
                pub fn strCtx(self: *Self, key: []const u8, val: []const u8) !void {
                    try self.addCtx(key, "{s}", false, .{val});
                }
                /// Returns an event that at the given log level 
                pub fn event(self: *Self, comptime lvl: LevelType) !Event(writerType, fmtMode, lvl) {
                    var newEvent = try Event(writerType, fmtMode, lvl).new(self.w);
                    try newEvent.buf.writer().writeAll(self.ctx.data.constSlice());
                    return newEvent;
                }
                /// Log a message at this logger's level
                pub fn print(self: *Self, msg: []const u8) !void {
                    // Filter out lower log levels
                    comptime if (@enumToInt(logLevel) > @enumToInt(conf.logLevelFilter) or (logLevel == .off)) {
                        return;
                    };
                    var ev = try self.event(logLevel);
                    try ev.msg(msg);
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
    var logger = try logMan.Logger(@TypeOf(writer), .plain, .debug).new(writer);
    // This won't be printed because global log level is .off
    try logger.print("hey there");
    try std.testing.expectEqualStrings("", arr.items);
}

test "logger print plain" {
    var arr = std.ArrayList(u8).init(test_allocator);
    defer arr.deinit();
    const writer = arr.writer();

    const conf = comptime LogConfig.testMode();
    const logMan = LogManager(conf);
    var logger = try logMan.Logger(@TypeOf(writer), .plain, .debug).new(writer);
    try logger.print("hey there");
    try std.testing.expectEqualStrings("0 DBG message=hey there\n", arr.items);
}

test "logger print json" {
    var arr = std.ArrayList(u8).init(test_allocator);
    defer arr.deinit();
    const writer = arr.writer();

    const conf = comptime LogConfig.testMode();
    const logMan = LogManager(conf);
    var logger = try logMan.Logger(@TypeOf(writer), .json, .debug).new(writer);
    try logger.print("hey there");
    const output =
        \\{"time":0,"level":"debug","message":"hey there"}
    ++ "\n";
    try std.testing.expectEqualStrings(output, arr.items);
}

test "logger event, no send or msg" {
    var arr = std.ArrayList(u8).init(test_allocator);
    defer arr.deinit();
    const writer = arr.writer();

    const conf = comptime LogConfig.testMode();
    const logMan = LogManager(conf);
    var logger = try logMan.Logger(@TypeOf(writer), .json, .debug).new(writer);
    var ev = try logger.event(.debug);
    try ev.str("Hey", "This is a field");
    try ev.str("Hey2", "This is also a field");
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
    var logger = try logMan.Logger(@TypeOf(writer), .json, .debug).new(writer);
    var ev = try logger.event(.debug);
    try ev.str("Hey", "This is a field");
    try ev.str("Hey2", "This is also a field");
    try ev.msg("Here's my message");
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
    var logger = try logMan.Logger(@TypeOf(writer), .json, .debug).new(writer);
    var i: u8 = 100 / 2;
    var ev = try logger.event(.debug);
    try ev.str("Hey", "This is a field");
    try ev.str("Hey2", "This is also a field");
    try ev.num("Value1", 10);
    try ev.num("Value2", 199.2);
    try ev.num("Value3", i);
    try ev.msg("Here's my message");
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
test "logger event json boolean" {
    var arr = std.ArrayList(u8).init(test_allocator);
    defer arr.deinit();
    const writer = arr.writer();
    const conf = comptime LogConfig.testMode();
    const logMan = LogManager(conf);
    var logger = try logMan.Logger(@TypeOf(writer), .json, .debug).new(writer);
    var i: u8 = 100 / 2;
    var ev= try logger.event(.debug);
    try ev.str("Hey", "This is a field");
    try ev.str("Hey2", "This is also a field");
    try ev.num("Value1", 10);
    try ev.num("Value2", 199.2);
    try ev.num("Value3", i);
    try ev.boolean("Value4", true);
    try ev.boolean("Value5", false);
    try ev.msg("Here's my message");
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
        \\"Value4":true,
        ++
        \\"Value5":false,
        ++
        \\"message":"Here's my message"}
    ++ "\n";
    try std.testing.expectEqualStrings(output, arr.items);
}
test "logger event json boolean, with context" {
    var arr = std.ArrayList(u8).init(test_allocator);
    defer arr.deinit();
    const writer = arr.writer();
    const conf = comptime LogConfig.testMode();
    const logMan = LogManager(conf);
    var logger = try logMan.Logger(@TypeOf(writer), .json, .debug).new(writer);
    try logger.strCtx("Ctx1", "contextVal");
    try logger.booleanCtx("Ctx2", true);
    try logger.numCtx("Ctx3", 14.3);
    var i: u8 = 100 / 2;
    var ev= try logger.event(.debug);
    try ev.str("Hey", "This is a field");
    try ev.str("Hey2", "This is also a field");
    try ev.num("Value1", 10);
    try ev.num("Value2", 199.2);
    try ev.num("Value3", i);
    try ev.boolean("Value4", true);
    try ev.msg("Here's my message");
    const output =
        \\{"time":0,
        ++
        \\"level":"debug",
        ++
        \\"Ctx1":"contextVal",
        ++
        \\"Ctx2":true,
        ++
        \\"Ctx3":14.3,
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
        \\"Value4":true,
        ++
        \\"message":"Here's my message"}
    ++ "\n";
    try std.testing.expectEqualStrings(output, arr.items);
}
test "logger event json boolean, with new logger context" {
    var arr = std.ArrayList(u8).init(test_allocator);
    defer arr.deinit();
    const writer = arr.writer();
    const conf = comptime LogConfig.testMode();
    const logMan = LogManager(conf);
    var logger = try logMan.Logger(@TypeOf(writer), .json, .debug).new(writer);
    try logger.strCtx("Ctx1", "contextVal");
    try logger.booleanCtx("Ctx2", true);
    try logger.numCtx("Ctx3", 14.3);
    var logger2 = try logger.sublogger(.err);
    try logger2.strCtx("Ctx4", "logger2context");
    // this context should not show up because it's on the original logger, not logger2
    try logger.strCtx("Ctx5", "logger1context");
    var i: u8 = 100 / 2;
    var ev = try logger2.event(.debug);
    try ev.str("Hey", "This is a field");
    try ev.str("Hey2", "This is also a field");
    try ev.num("Value1", 10);
    try ev.num("Value2", 199.2);
    try ev.num("Value3", i);
    try ev.boolean("Value4", true);
    try ev.msg("Here's my message");
    const output =
        \\{"time":0,
        ++
        \\"level":"debug",
        ++
        \\"Ctx1":"contextVal",
        ++
        \\"Ctx2":true,
        ++
        \\"Ctx3":14.3,
        ++
        \\"Ctx4":"logger2context",
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
        \\"Value4":true,
        ++
        \\"message":"Here's my message"}
    ++ "\n";
    try std.testing.expectEqualStrings(output, arr.items);
}
