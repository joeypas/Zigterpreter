const std = @import("std");
const Allocator = @import("Allocator");
const fs = std.fs;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const file = try fs.cwd().createFile("testf", .{ .read = true });
    defer file.close();

    var rng = std.rand.DefaultPrng.init(12345);
    const random = rng.random();

    var i: usize = 0;

    while (i < 2000) : (i += 1) {
        var line = std.ArrayList(u8).init(arena.allocator());
        defer _ = arena.reset(.retain_capacity);

        var j: usize = 0;

        const a = random.intRangeAtMost(i32, 1, 1000);
        const first = try std.fmt.allocPrint(arena.allocator(), "{d} ", .{a});
        try line.appendSlice(first);
        while (j < random.intRangeAtMost(usize, 1, 20)) : (j += 1) {
            const b = random.intRangeAtMost(i32, 1, 1000);
            const op = switch (random.intRangeAtMost(u8, 0, 3)) {
                0 => "+",
                1 => "-",
                2 => "*",
                3 => "/",
                else => unreachable,
            };

            const temp = try std.fmt.allocPrint(arena.allocator(), "{s} {d} ", .{ op, b });
            try line.appendSlice(temp);
        }
        try line.appendSlice("\n");

        try file.writer().writeAll(line.items);
    }
}
