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
        pub fn Event(
            comptime writerType: type,
            comptime fmtMode: FormatMode,
            comptime logLevel: LevelType,
        ) type {
            return struct {
                w: writerType,
                // buf: std.ArrayList(u8),

                const Self = @This();
                pub fn New(w: writerType) !Self {
                    try w.writeAll(
                       "{\"level\":\"" ++ logLevel.asText() ++ "\"," 
                    );
                    return Self{
                        .w = w,
                    };
                }

                /// Add a key:value pair to this event
                pub fn Add(
                    self: *Self, 
                    key: []const u8, 
                    comptime valFmtStr: []const u8, 
                    args: anytype
                ) !void {
                    comptime if (@enumToInt(logLevel) > @enumToInt(globalLogLevel)){
                        return;
                    };
                    switch (fmtMode) {
                        .json => {
                            try self.w.print("\"{s}\":\"", .{key});
                            try self.w.print(valFmtStr, args);
                            try self.w.print("\",", .{});
                        },
                        else => unreachable, // TODO: implement
                    }
                }
                /// Send this event to the writer with no message.
                /// The event should then be discarded.
                pub fn Send(self: *Self) !void {
                    comptime if (@enumToInt(logLevel) > @enumToInt(globalLogLevel)){
                        return;
                    };
                    switch (fmtMode) {
                        .json => {
                            try self.w.print("\"time\":{}}}\n", .{getTime()});
                        },
                        else => unreachable, // TODO: implement
                    }
                }
                /// Send this event to the writer with the given message.
                pub fn Msg(self: *Self, msg: []const u8) !void {
                    comptime if (@enumToInt(logLevel) > @enumToInt(globalLogLevel)){
                        return;
                    };
                    switch (fmtMode) {
                        .json => {
                            try self.Add("message", "{s}", .{msg});
                        },
                        else => unreachable, // TODO: implement
                    }
                    try self.Send();
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

        fn getTime() i64 {
            return switch (timeFormat) {
                .unixSecs => std.time.timestamp(),
                .testMode => 0,
            };
        }

        pub fn Logger(
            comptime writerType: type, 
            comptime fmtMode: FormatMode,
            comptime logLevel: LevelType,
        ) type {
            return struct {
                w: writerType,
                ctx: []u8,

                const Self = @This();
                pub fn getLevel() LevelType {
                    return logLevel;
                }
                pub fn Level(
                    self: *Self, 
                    comptime lvl: LevelType,
                ) Logger(writerType, fmtMode, lvl) {
                    return Logger(writerType, fmtMode, lvl){
                        .w = self.w,
                        .ctx = self.ctx,
                    };
                }
                pub fn WithLevel(
                    self: *Self, 
                    comptime lvl: LevelType
                ) !Event(writerType, fmtMode, lvl) {
                    return Event(writerType, fmtMode, lvl).New(self.w);
                }
                pub fn Print(self: *Self, msg: []const u8) !void {
                    comptime if (@enumToInt(logLevel) > @enumToInt(globalLogLevel)){
                        return;
                    };
                    const timeVal = getTime();
                    switch (fmtMode) {
                        .json => {
                            try self.w.print(
                                "{{" ++
                                "\"time\":{}," ++
                                "\"level\":\"{s}\"," ++
                                "\"message\":\"{s}\"" ++
                                "}}",
                                .{timeVal, logLevel.asText(), msg});
                        },
                        .plain => {
                            try self.w.writeAll(
                                levelSmallStr(logLevel) 
                                ++ " "
                            );
                            try self.w.writeAll(msg);
                        },
                        .pretty => {
                            const colorPrefix = switch(logLevel) {
                                .panic, .fatal, .err => "\x1b[31m",
                                .warn => "\x1b[33m",
                                .info => "\x1b[32m",
                                .debug => "\x1b[35m",
                                .trace => "\x1b[36m",
                                else => "",
                            };
                            try self.w.writeAll(
                                colorPrefix
                                ++ levelSmallStr(logLevel)
                                ++ "\x1b[0m "
                            );
                            try self.w.writeAll(msg);
                        },
                    }
                    return self.w.writeAll("\n");
                }
            };
        }
    };
}
