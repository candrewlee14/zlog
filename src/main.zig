const std = @import("std");
const zlog = @import("zlog.zig");
const logger = &zlog.globalPrettyLogger;

pub fn main() anyerror!void {
    try logger.print("hey there");
    var sublogger = try logger.sublogger(.warn);
    try sublogger.print("look, a warning!");

    {
        var ev = try logger.event(.err);
        try ev.str("Hey2", "This is also a field");
        try ev.num("Value1", 10);
        try ev.msgf("This is using msgf to append a {s} here and {d} here", 
            .{"string", 10.3});
    }

    var i : u16 = 0;
    while (i < 1000) : (i += 1) {
        var ev = try logger.event(.warn);
        var j : u8 = 0;
        while (j < 5) : (j += 1) {
            try ev.str("Field1", "Look at my cool value here");
            try ev.num("Field2", i+j);
            try ev.boolean("Field3", i*j % 7 == 0);
        }
        try ev.send();
    }
}
