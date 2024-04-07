const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const astree = @import("ast.zig");
const Parser = @import("parser.zig").Parser;
const Lexer = @import("lexer.zig").Lexer;

const AST = astree.AST;
const TreeType = astree.TreeType;

// INTERPRETER CODE
// The interpreter takes in an abstract syntax tree and returns the result of the expression
const Interpreter = struct {
    parser: *Parser,

    pub fn init(parser: *Parser) Interpreter {
        return Interpreter{
            .parser = parser,
        };
    }

    // Recursively visit the tree and return the result
    fn visit(self: *Interpreter, node: *AST) i128 {
        _ = self;
        return node.visit();
    }

    pub fn interpret(self: *Interpreter) !i128 {
        const tree = try self.parser.expr();
        const res = self.visit(tree);
        return res;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const stdout = std.io.getStdOut();
    const stdin = std.io.getStdIn();
    defer stdout.close();
    defer stdin.close();

    const out = stdout.writer();
    const in = stdin.reader();

    _ = args.next();

    if (args.next()) |file_name| {
        const file = try std.fs.cwd().openFile(file_name, .{ .mode = .read_only });
        defer file.close();
        const stats = try file.stat();
        const file_contents = try file.readToEndAlloc(allocator, stats.size);
        defer allocator.free(file_contents);

        var sp = std.mem.split(u8, file_contents, "\n");

        var i: usize = 0;

        while (true) : (i += 1) {
            if (sp.next()) |line| {
                if (line.len == 0) {
                    break;
                }
                var lex = Lexer.init(line, allocator);
                var parser = Parser.init(allocator, &lex) catch |err| {
                    try out.print("Error on line: {d}\n{any}\n", .{ i, err });
                    break;
                };
                defer parser.deinit();
                var int = Interpreter.init(&parser);
                const result = int.interpret() catch |err| {
                    try out.print("Error on line: {d}\n{any}\n", .{ i, err });
                    break;
                };

                try out.print("Line {d}: {d}\n", .{ i, result });
            } else {
                break;
            }
        }
    } else {
        const exit: []const u8 = "exit";
        var condition = true;

        while (condition) {
            try out.print(">> ", .{});
            const input = try in.readUntilDelimiterOrEofAlloc(allocator, '\n', 1024);
            if (input) |text| {
                defer allocator.free(input.?);
                if (std.mem.eql(u8, exit, text)) {
                    condition = false;
                    break;
                }
                var lex = Lexer.init(text, allocator);
                var parser = Parser.init(allocator, &lex) catch |err| {
                    try out.print("Error: {any}\n", .{err});
                    continue;
                };
                defer parser.deinit();
                var int = Interpreter.init(&parser);

                const result = int.interpret() catch |err| {
                    try out.print("Error: {any}\n", .{err});
                    continue;
                };
                try out.print("{d}\n", .{result});
            } else {
                continue;
            }
        }
    }
}
