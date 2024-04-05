const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const types = @import("types.zig");
const astree = @import("ast.zig");

const Token = types.Token;
const TType = types.TType;
const TokenError = types.TokenError;
const CharNum = types.CharNum;
const AST = astree.AST;
const TreeType = astree.TreeType;

// LEXER CODE
// The lexer takes in a string and returns a list of tokens
const Lexer = struct {
    text: []const u8,
    pos: usize,
    current_char: ?u8,
    allocator: Allocator,

    // Initialize the lexer with the input string
    pub fn init(text: []const u8, alloc: Allocator) Lexer {
        if (text.len < 1) {
            return Lexer{
                .text = text,
                .allocator = alloc,
                .pos = 0,
                .current_char = undefined,
            };
        } else {
            return Lexer{
                .text = text,
                .allocator = alloc,
                .pos = 0,
                .current_char = text[0],
            };
        }
    }

    fn peek(self: *Lexer) ?u8 {
        const peek_pos = self.pos + 1;
        if (peek_pos > self.text.len - 1) {
            return null;
        } else {
            return self.text[peek_pos];
        }
    }

    // Advance the current character
    fn advance(self: *Lexer) void {
        self.pos += 1;
        if (self.pos > self.text.len - 1) {
            self.current_char = null;
        } else {
            self.current_char = self.text[self.pos];
        }
    }

    // Skip whitespace
    fn skipWhitespace(self: *Lexer) void {
        while (self.current_char != null and std.ascii.isWhitespace(self.current_char.?)) {
            self.advance();
        }
    }

    fn id(self: *Lexer) TokenError!Token {
        var i: usize = self.pos;
        while (self.current_char != null and std.ascii.isAlphanumeric(self.current_char.?)) {
            self.advance();
        }

        const result = self.text[i..self.pos];
        if (std.mem.eql(u8, result, "BEGIN")) {
            return Token.init(.BEGIN, .{ .Str = "BEGIN" });
        } else if (std.mem.eql(u8, result, "END")) {
            return Token.init(.END, .{ .Str = "END" });
        } else {
            return Token.init(.ID, .{ .Str = result });
        }
    }

    // Parse a number
    fn integer(self: *Lexer) !i128 {
        var num = ArrayList(u8).init(self.allocator);
        defer num.deinit();

        while (self.current_char != null and std.ascii.isDigit(self.current_char.?)) {
            try num.append(self.current_char.?);
            self.advance();
        }

        const ret = try std.fmt.parseInt(i128, num.items, 10);
        return ret;
    }

    // Get the next token
    pub fn getNextToken(self: *Lexer) TokenError!Token {
        while (self.current_char != null) {
            if (std.ascii.isWhitespace(self.current_char.?)) {
                self.skipWhitespace();
                continue;
            }

            if (std.ascii.isDigit(self.current_char.?)) {
                const num = self.integer() catch return TokenError.InvalidCharacter;
                return Token.init(TType.INTEGER, .{ .Num = num });
            }

            if (std.ascii.isAlphabetic(self.current_char.?)) {
                const _id = try self.id();
                return _id;
            }

            if (self.current_char == ':' and self.peek() == '=') {
                self.advance();
                self.advance();
                return Token.init(TType.ASSIGN, .{ .Str = ":=" });
            }

            if (self.current_char == ';') {
                self.advance();
                return Token.init(TType.SEMI, .{ .Char = ';' });
            }

            if (self.current_char == '.') {
                self.advance();
                return Token.init(TType.DOT, .{ .Char = '.' });
            }

            if (self.current_char == '+') {
                self.advance();
                return Token.init(TType.PLUS, .{ .Char = '+' });
            }

            if (self.current_char == '-') {
                self.advance();
                return Token.init(TType.MINUS, .{ .Char = '-' });
            }

            if (self.current_char == '*') {
                self.advance();
                return Token.init(TType.MULTI, .{ .Char = '*' });
            }

            if (self.current_char == '/') {
                self.advance();
                return Token.init(TType.DIVIS, .{ .Char = '/' });
            }

            if (self.current_char == '(') {
                self.advance();
                return Token.init(TType.LPAREN, .{ .Char = '(' });
            }

            if (self.current_char == ')') {
                self.advance();
                return Token.init(TType.RPAREN, .{ .Char = ')' });
            }

            return TokenError.InvalidToken;
        }

        return Token.init(TType.EOF, undefined);
    }
};

test "Lexer" {
    const text = "BEGIN a := 2; END.\n";
    var lex = Lexer.init(text, std.testing.allocator);
    const first = try lex.getNextToken();
    const second = try lex.getNextToken();

    const str1 = try first.str(std.testing.allocator);
    const str2 = try second.str(std.testing.allocator);
    defer std.testing.allocator.free(str1);
    defer std.testing.allocator.free(str2);

    std.debug.print("{s}\n", .{str1});
    std.debug.print("{s}\n", .{str2});
}

// PARSER CODE
// The parser takes in a list of tokens and returns an abstract syntax tree
const Parser = struct {
    current_token: Token,
    lexer: *Lexer,
    allocator: Allocator,
    head: *AST,

    // Initialize the parser with the lexer and a list
    // to keep track of allocated nodes
    pub fn init(alloc: Allocator, lexer: *Lexer) !Parser {
        return Parser{
            .allocator = alloc,
            .lexer = lexer,
            .current_token = try lexer.getNextToken(),
            .head = undefined,
        };
    }

    // Deinitialize the parser and free all the nodes
    pub fn deinit(self: *Parser) void {
        self.delete(self.head);
    }

    // Recursively delete the tree
    fn delete(self: *Parser, tree: *AST) void {
        switch (tree.*) {
            .BinOp => |branch| {
                self.delete(branch.right);
                self.delete(branch.left);
                self.allocator.destroy(tree);
            },
            .Num => self.allocator.destroy(tree),
            .UnaryOp => |branch| {
                self.delete(branch.expr);
                self.allocator.destroy(tree);
            },
        }
    }

    // Factor is the smallest unit of the expression
    pub fn factor(self: *Parser) TokenError!*AST {
        const token = self.current_token;
        if (token.Type == TType.PLUS) {
            try self.eat(TType.PLUS);
            const node = self.allocator.create(AST) catch return TokenError.Mem;
            const exp = try self.factor();
            node.* = AST{
                .UnaryOp = .{
                    .token = token,
                    .expr = exp,
                },
            };
        } else if (token.Type == TType.MINUS) {
            try self.eat(TType.MINUS);
            const node = self.allocator.create(AST) catch return TokenError.Mem;
            const exp = try self.factor();
            node.* = AST{
                .UnaryOp = .{
                    .token = token,
                    .expr = exp,
                },
            };
            return node;
        } else if (token.Type == TType.INTEGER) {
            try self.eat(TType.INTEGER);
            const node = self.allocator.create(AST) catch return TokenError.Mem;
            node.* = AST{ .Num = .{ .token = token } };
            return node;
        } else if (token.Type == TType.LPAREN) {
            try self.eat(TType.LPAREN);
            const result = try self.expr();
            try self.eat(TType.RPAREN);
            return result;
        }
        return TokenError.InvalidToken;
    }

    // Term is the next level of the expression
    pub fn term(self: *Parser) TokenError!*AST {
        var result = try self.factor();

        while (self.current_token.Type == TType.MULTI or self.current_token.Type == TType.DIVIS) {
            const token = self.current_token;
            if (token.Type == TType.MULTI) {
                try self.eat(TType.MULTI);
            } else if (token.Type == TType.DIVIS) {
                try self.eat(TType.DIVIS);
            }

            const part = try self.factor();
            const node = self.allocator.create(AST) catch return TokenError.Mem;
            const branch = AST{
                .BinOp = .{
                    .left = result,
                    .right = part,
                    .token = token,
                },
            };
            node.* = branch;

            result = node;
        }

        return result;
    }

    // Eat a token if it matches the current token
    pub fn eat(self: *Parser, token_type: TType) TokenError!void {
        if (self.current_token.Type == token_type) {
            self.current_token = try self.lexer.getNextToken();
        } else {
            std.debug.print("{any}, {any}\n", .{ self.current_token.Type, token_type });
            return TokenError.InvalidType;
        }
    }

    // Expression is the highest level of the expression
    pub fn expr(self: *Parser) TokenError!*AST {
        var result = try self.term();

        while (self.current_token.Type == TType.PLUS or self.current_token.Type == TType.MINUS) {
            const token = self.current_token;
            if (token.Type == TType.PLUS) {
                try self.eat(TType.PLUS);
            } else if (token.Type == TType.MINUS) {
                try self.eat(TType.MINUS);
            }

            const part = try self.term();
            const node = self.allocator.create(AST) catch return TokenError.Mem;
            const branch = AST{
                .BinOp = .{
                    .left = result,
                    .right = part,
                    .token = token,
                },
            };
            node.* = branch;
            result = node;
        }

        self.head = result;

        return result;
    }
};

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
