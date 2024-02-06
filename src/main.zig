const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Type = std.builtin.Type;

// Token Types
const TType = enum {
    INTEGER,
    PLUS,
    MINUS,
    MULTI,
    DIVIS,
    EOF,
    LPAREN,
    RPAREN,
};

// Type to hold either a character or a number
const CharNum = union(enum) {
    Char: u8,
    Num: i64,
};

// Struct to hold the token type and the value
const Token = struct {
    Type: TType,
    value: CharNum,

    pub fn init(Ty: TType, val: CharNum) Token {
        return Token{
            .Type = Ty,
            .value = val,
        };
    }

    pub fn str(self: Token, allocator: Allocator) std.fmt.AllocPrintError![]u8 {
        return std.fmt.allocPrint(allocator, "Token({s}, {c})", .{ @tagName(self.Type), self.value });
    }
};

const TokenError = error{ InvalidToken, InvalidCharacter, InvalidType, Mem };

// LEXER CODE
// The lexer takes in a string and returns a list of tokens
const Lexer = struct {
    text: []const u8,
    pos: usize,
    current_char: ?u8,

    // Initialize the lexer with the input string
    pub fn init(text: []const u8) Lexer {
        return Lexer{
            .text = text,
            .pos = 0,
            .current_char = text[0],
        };
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

    // Parse a number
    fn integer(self: *Lexer) !i64 {
        const alloc = std.heap.page_allocator;
        var num = ArrayList(u8).init(alloc);
        defer num.deinit();

        while (self.current_char != null and std.ascii.isDigit(self.current_char.?)) {
            try num.append(self.current_char.?);
            self.advance();
        }

        const ret = try std.fmt.parseInt(i64, num.items, 10);
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

// PARSER CODE
// The parser takes in a list of tokens and returns an abstract syntax tree
const Parser = struct {
    current_token: Token,
    lexer: *Lexer,
    allocator: Allocator,
    nodeList: ArrayList(*Tree(Token)),

    // Initialize the parser with the lexer and a list
    // to keep track of allocated nodes
    pub fn init(alloc: Allocator, lexer: *Lexer) !Parser {
        return Parser{
            .allocator = alloc,
            .lexer = lexer,
            .current_token = try lexer.getNextToken(),
            .nodeList = ArrayList(*Tree(Token)).init(alloc),
        };
    }

    // Deinitialize the parser and free all the nodes
    pub fn deinit(self: *Parser) void {
        for (self.nodeList.items) |node| {
            self.allocator.destroy(node);
        }
        self.nodeList.deinit();
    }

    // Factor is the smallest unit of the expression
    pub fn factor(self: *Parser) TokenError!*Tree(Token) {
        const token = self.current_token;
        if (token.Type == TType.INTEGER) {
            try self.eat(TType.INTEGER);
            const node = self.allocator.create(Tree(Token)) catch return TokenError.Mem;
            node.* = Tree(Token){ .Data = token };
            self.nodeList.append(node) catch return TokenError.Mem;
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
    pub fn term(self: *Parser) TokenError!*Tree(Token) {
        var result = try self.factor();

        while (self.current_token.Type == TType.MULTI or self.current_token.Type == TType.DIVIS) {
            const token = self.current_token;
            if (token.Type == TType.MULTI) {
                try self.eat(TType.MULTI);
            } else if (token.Type == TType.DIVIS) {
                try self.eat(TType.DIVIS);
            }

            const part = try self.factor();
            const node = self.allocator.create(Tree(Token)) catch return TokenError.Mem;
            const branch = Tree(Token){
                .Branch = .{
                    .left = result,
                    .right = part,
                    .Data = token,
                },
            };
            node.* = branch;
            self.nodeList.append(node) catch return TokenError.Mem;

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
    pub fn expr(self: *Parser) TokenError!*Tree(Token) {
        // TODO: implement pemdas
        //
        var result = try self.term();

        while (self.current_token.Type == TType.PLUS or self.current_token.Type == TType.MINUS) {
            const token = self.current_token;
            if (token.Type == TType.PLUS) {
                try self.eat(TType.PLUS);
            } else if (token.Type == TType.MINUS) {
                try self.eat(TType.MINUS);
            }

            const part = try self.term();
            const node = self.allocator.create(Tree(Token)) catch return TokenError.Mem;
            const branch = Tree(Token){
                .Branch = .{
                    .left = result,
                    .right = part,
                    .Data = token,
                },
            };
            node.* = branch;
            self.nodeList.append(node) catch return TokenError.Mem;
            result = node;
        }
        return result;
    }
};

// The tree type is a union of a data type and a branch type
// basically the AST type
pub fn Tree(comptime T: type) type {
    return union(enum) {
        Data: T,

        Branch: struct {
            left: *Tree(T),
            right: *Tree(T),
            Data: T,
        },
    };
}

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
    fn visit(self: *Interpreter, node: *Tree(Token)) i64 {
        switch (node.*) {
            .Branch => |branch| {
                if (branch.Data.Type == TType.PLUS) {
                    return self.visit(branch.left) + self.visit(branch.right);
                } else if (branch.Data.Type == TType.MINUS) {
                    return self.visit(branch.left) - self.visit(branch.right);
                } else if (branch.Data.Type == TType.MULTI) {
                    return self.visit(branch.left) * self.visit(branch.right);
                } else if (branch.Data.Type == TType.DIVIS) {
                    return @divTrunc(self.visit(branch.left), self.visit(branch.right));
                } else {
                    return 0;
                }
            },
            .Data => |data| {
                switch (data.value) {
                    .Num => return data.value.Num,
                    .Char => return 0,
                }
            },
        }
    }

    pub fn interpret(self: *Interpreter) !i64 {
        const tree = try self.parser.expr();
        const res = self.visit(tree);
        return res;
    }
};

test {
    const text = "(5+5)*5\n";
    var lex = Lexer.init(text);
    var parser = try Parser.init(std.testing.allocator, &lex);
    defer parser.deinit();
    var int = Interpreter.init(&parser);
    const result = try int.interpret();
    try std.testing.expect(result == 50);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const stdout = std.io.getStdOut();
    const stdin = std.io.getStdIn();
    defer stdout.close();
    defer stdin.close();

    const out = stdout.writer();
    const in = stdin.reader();
    const allocator = gpa.allocator();

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
            var lex = Lexer.init(text);
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
