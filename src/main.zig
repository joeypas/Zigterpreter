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
};

const Token = struct {
    Type: TType,
    value: u8,

    pub fn init(Ty: TType, val: u8) Token {
        return Token{
            .Type = Ty,
            .value = val,
        };
    }

    pub fn str(self: Token, allocator: Allocator) std.fmt.AllocPrintError![]u8 {
        return std.fmt.allocPrint(allocator, "Token({s}, {c})", .{ @tagName(self.Type), self.value });
    }
};

const TokenError = error{
    InvalidToken,
    InvalidCharacter,
    InvalidType,
};

const Lexer = struct {
    text: []const u8,
    pos: usize,
    current_char: ?u8,

    pub fn init(text: []const u8) Lexer {
        return Lexer{
            .text = text,
            .pos = 0,
            .current_char = text[0],
        };
    }

    fn advance(self: *Lexer) void {
        self.pos += 1;
        if (self.pos > self.text.len - 1) {
            self.current_char = null;
        } else {
            self.current_char = self.text[self.pos];
        }
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.current_char != null and std.ascii.isWhitespace(self.current_char.?)) {
            self.advance();
        }
    }

    fn integer(self: *Lexer) !u8 {
        const alloc = std.heap.page_allocator;
        var num = ArrayList(u8).init(alloc);
        defer num.deinit();

        while (self.current_char != null and std.ascii.isDigit(self.current_char.?)) {
            try num.append(self.current_char.?);
            self.advance();
        }

        const ret = try std.fmt.parseInt(u8, num.items, 10);
        return ret;
    }

    pub fn getNextToken(self: *Lexer) TokenError!Token {
        while (self.current_char != null) {
            if (std.ascii.isWhitespace(self.current_char.?)) {
                self.skipWhitespace();
                continue;
            }

            if (std.ascii.isDigit(self.current_char.?)) {
                const num = self.integer() catch 0;
                return Token.init(TType.INTEGER, num);
            }

            if (self.current_char == '+') {
                self.advance();
                return Token.init(TType.PLUS, '+');
            }

            if (self.current_char == '-') {
                self.advance();
                return Token.init(TType.MINUS, '-');
            }

            if (self.current_char == '*') {
                self.advance();
                return Token.init(TType.MULTI, '*');
            }

            if (self.current_char == '/') {
                self.advance();
                return Token.init(TType.DIVIS, '/');
            }

            return TokenError.InvalidToken;
        }

        return Token.init(TType.EOF, undefined);
    }
};

const Interpreter = struct {
    current_token: Token,
    lexer: *Lexer,

    pub fn init(lexer: *Lexer) !Interpreter {
        return Interpreter{
            .lexer = lexer,
            .current_token = try lexer.getNextToken(),
        };
    }

    pub fn factor(self: *Interpreter) !u8 {
        const token = self.current_token;
        try self.eat(TType.INTEGER);
        return token.value;
    }

    pub fn term(self: *Interpreter) !u8 {
        var result = try self.factor();

        while (self.current_token.Type == TType.MULTI or self.current_token.Type == TType.DIVIS) {
            const token = self.current_token;
            if (token.Type == TType.MULTI) {
                try self.eat(TType.MULTI);
                const part = try self.factor();
                result = result * part;
            } else if (token.Type == TType.DIVIS) {
                try self.eat(TType.DIVIS);
                const part = try self.factor();
                result = result / part;
            }
        }

        return result;
    }

    pub fn eat(self: *Interpreter, token_type: TType) !void {
        if (self.current_token.Type == token_type) {
            self.current_token = try self.lexer.getNextToken();
        } else {
            std.debug.print("{any}, {any}\n", .{ self.current_token.Type, token_type });
            return TokenError.InvalidType;
        }
    }

    pub fn expr(self: *Interpreter) !u8 {
        // TODO: implement pemdas
        //
        var result = try self.term();

        while (self.current_token.Type == TType.PLUS or self.current_token.Type == TType.MINUS) {
            const token = self.current_token;
            if (token.Type == TType.PLUS) {
                try self.eat(TType.PLUS);
                const part = try self.term();
                result = result + part;
            } else if (token.Type == TType.MINUS) {
                try self.eat(TType.MINUS);
                const part = try self.term();
                result = result - part;
            }
        }
        return result;
    }
};

test {
    const text = "5+5*5\n";
    var lex = Lexer.init(text);
    var int = try Interpreter.init(&lex);
    const result = try int.expr();
    try std.testing.expect(result == 30);
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
            var int = try Interpreter.init(&lex);

            const result = try int.expr();
            try out.print("{d}\n", .{result});
        } else {
            continue;
        }
    }
}
