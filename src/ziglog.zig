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
        ) type {
            return struct {
                w: writerType,
                buf: std.ArrayList(u8),
                lvl: LevelType,

                const Self = @This();
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

        const FormatMode = enum {
            json,
            pretty,
            plain,
        };

        pub fn Logger(
            comptime writerType: type, 
            comptime fmMode: FormatMode,
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
                ) Logger(writerType, fmMode, lvl) {
                    return Logger(writerType, fmMode, lvl){
                        .w = self.w,
                        .ctx = self.ctx,
                    };
                }
                pub fn Print(self: *Self, msg: []const u8) !void {
                    comptime if (@enumToInt(logLevel) > @enumToInt(globalLogLevel)){
                        return;
                    };
                    const timeVal = switch (timeFormat) {
                        .unixSecs => std.time.timestamp(),
                        .testMode => 0,
                    };
                    switch (fmMode) {
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
