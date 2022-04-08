# zlog
A [zerolog](https://github.com/rs/zerolog)-inspired log library for Zig.

## Features
 - Blazing fast
 - Zero allocations
 - Leveled logging
 - Contextual logging 
 - JSON & Pretty logging formats

## Getting Started
### Simple Logging Example
For simple logging, import a global logger
```zig
const zlog = @import("zlog.zig");
const log= &zlog.globalJsonLogger;
// You could also use globalPrettyLogger, globalPlainLogger 

pub fn main() anyerror!void {
    try log.print("Hello!");
}
// Output: {"time":1516134303,"level":"debug","message":"hello world"}
```
**Note:** By default, log writes to StdErr at the log level of `.debug`

**Note:** The default log level **global filter** depends on the build mode:
- .Debug => .debug
- .ReleaseSafe => .info
- .ReleaseFast, .ReleaseSmall => .warn

### Contextual Logging
Loggers create events, which do the log writing.
You can add strongly-typed key:value pairs to an event context.
Then the `msg`, `msgf`, or `send` method will write the event to the log.
**Note:** Without calling any of those 3 methods, the log will not be written.

```zig
const zlog = @import("zlog.zig");
const log = &zlog.globalJsonLogger;

pub fn main() anyerror!void {
    var ev = try log.event(.debug);
    try ev.str("Scale", "833 cents");
    try ev.num("Interval", 833.09);
    try ev.msg("Fibonacci is everywhere");

    var ev2 = try log.event(.debug);
    try ev2.str("Name", "Tom");
    try ev2.send();
}
// Output: {"level":"debug","Scale":"833 cents","Interval":833.09,"time":1562212768,"message":"Fibonacci is everywhere"}
// Output: {"level":"debug","Name":"Tom","time":1562212768}
```

You can add context to a logger so that every event it creates also has that context.
You can also create subloggers that use the parent logger's context along with their own context.

```zig
const zlog = @import("zlog.zig");
const log = &zlog.globalJsonLogger;

pub fn main() anyerror!void {
    try log.strCtx("component", "foo");

    var ev = try log.event(.info);
    try ev.msg("hello world");

    // create sublogger, bringing along log's context 
    var sublog = log.sublogger(.info);
    try log.numCtx("num", 10);

    var ev2 = try sublog.event(.debug);
    try ev2.msg("hey there");
}
// Output: {"level":"info","time":1494567715,"component":"foo","message":"hello world"}
// Output: {"level":"info","time":1494567715,"component":"foo","num":10, "message":"hello world"}
```

### Leveled Logging

zlog allow for logging at the following levels (from highest to lowest):
- panic
- fatal
- error
- warn
- info
- debug
- trace

A comptime-known level will be passed into `log.event(LEVEL)` or `log.sublogger(LEVEL)`
for leveled logging.

To disable logging entirely, set the global log level filter to `.off`;

#### Setting Global Log Level Filter

```zig
const zlog = @import("zlog.zig");

// setting global log configuration
const logConf = zlog.LogConfig.default();
    .logLevelFilter = .info, // lowest allowed log level
    .timeFormat = .unixSecs, // format to print the time
    .eventBufSize = 1000, // buffer size for events, 1000 is the default
};
// creating a log manager with the set config
const logMan = zlog.LogManager(logConf);
// choosing a default writer to write logs into
const logWriter = std.io.getStdErr().writer();
// choosing a default log level for the logger
const loggerDefaultLevel = .info;

// Creating the logger
var log = logMan.Logger(@TypeOf(logWriter), .json, loggerDefaultLevel)
    .new(logWriter) catch @panic("Failed to create global JSON logger");

pub fn main() anyerror!void {
    var ev = try log.event(.debug);
    try ev.str("Scale", "833 cents");
    try ev.num("Interval", 833.09);
    try ev.msg("Fibonacci is everywhere");

    var ev2 = try log.event(.debug);
    try ev2.str("Name", "Tom");
    try ev2.send();
}
```
