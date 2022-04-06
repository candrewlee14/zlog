const std = @import("std");
const builtin = @import("builtin");

/// The default log level is based on build mode.
pub const default_level: LevelType = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe => .info,
    .ReleaseFast, .ReleaseSmall => .err,
};

const TimeFormat = enum {
    unixSecs,
    testMode,
};

const LevelType = enum {
    off,
    panic,
    fatal,
    err,
    warn,
    info,
    debug,
    trace,
    fn asText(self: LevelType) []const u8 {
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
};


pub fn LogManager(
    comptime globalLogLevel: LevelType,
    comptime timeFormat: TimeFormat,
) type {
    return struct {
        fn getTime() i128 {
            return switch (timeFormat) {
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
                timeVal: i128,
                // buf: std.ArrayList(u8),

                const Self = @This();
                // Creates new Event with current time
                pub fn New(w: writerType) !Self {
                    var timeVal = getTime();
                    switch (fmtMode) { 
                        .json => {
                            try w.writeAll("{");
                            try w.print("\"time\":{}", .{timeVal});
                            try w.writeAll(
                               ",\"level\":\"" ++ logLevel.asText() ++ "\"",
                            );
                        },
                        .pretty => {
                            try w.print("\x1b[90m{}\x1b[0m ", .{timeVal});
                            const lvlStr = switch(logLevel) {
                                .panic, .fatal, .err => "\x1b[31m",
                                .warn => "\x1b[33m",
                                .info => "\x1b[32m",
                                .debug => "\x1b[35m",
                                .trace => "\x1b[36m",
                                else => "",
                            } ++ levelSmallStr(logLevel) ++ "\x1b[0m";
                            try w.writeAll(lvlStr);
                        },
                        .plain => {
                            try w.print("{} ", .{timeVal});
                            try w.writeAll(levelSmallStr(logLevel));
                        },
                    }
                    return Self{
                        .w = w,
                        .timeVal = timeVal,
                    };
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
                    comptime if (@enumToInt(logLevel) > @enumToInt(globalLogLevel)){
                        return;
                    };
                    switch (fmtMode) {
                        .json => {
                            try self.w.print(",\"{s}\":", .{key});
                            if (!isNum) { try self.w.writeAll("\""); }
                            try self.w.print(valFmtStr, args);
                            if (!isNum) { try self.w.writeAll("\""); }
                        },
                        .plain => {
                            try self.w.print(" {s}=", .{key});
                            try self.w.print(valFmtStr, args);
                        },
                        .pretty => {
                            try self.w.print(" \x1b[90m{s}=\x1b[0m", .{key});
                            try self.w.print(valFmtStr, args);
                        },
                    }
                }
                pub fn str(self: *Self, key: []const u8, val: []const u8) !void {
                    try self.add(key, "{s}", false, .{val});
                }
                pub fn num(self: *Self, key: []const u8, val: anytype) !void {
                    const valTinfo = @typeInfo(@TypeOf(val));
                    switch (valTinfo) {
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
                    comptime if (@enumToInt(logLevel) > @enumToInt(globalLogLevel)){
                        return;
                    };
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
                    comptime if (@enumToInt(logLevel) > @enumToInt(globalLogLevel)){
                        return;
                    };
                    switch (fmtMode) {
                        .json, .plain, .pretty => {
                            try self.str("message", msgStr);
                        },
                    }
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
                    return Event(writerType, fmtMode, lvl).New(self.w);
                }
                pub fn print(self: *Self, msg: []const u8) !void {
                    comptime if (@enumToInt(logLevel) > @enumToInt(globalLogLevel)){
                        return;
                    };
                    var event = try self.withLevel(logLevel);
                    try event.msg(msg);
                }
            };
        }
    };
}
