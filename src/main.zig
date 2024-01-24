const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Type = std.builtin.Type;

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

const Interpreter = struct {
    text: []const u8,
    pos: usize,
    current_char: ?u8,
    current_token: *Token,

    pub fn init(text: []const u8) Interpreter {
        return Interpreter{
            .text = text,
            .pos = 0,
            .current_token = undefined,
            .current_char = text[0],
        };
    }

    fn advance(self: *Interpreter) void {
        self.pos += 1;
        if (self.pos > self.text.len - 1) {
            self.current_char = null;
        } else {
            self.current_char = self.text[self.pos];
        }
    }

    fn skipWhitespace(self: *Interpreter) void {
        while (self.current_char != null and std.ascii.isWhitespace(self.current_char.?)) {
            self.advance();
        }
    }

    fn integer(self: *Interpreter) !u8 {
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

    pub fn getNextToken(self: *Interpreter) TokenError!Token {
        while (self.current_char != null) {
            if (std.ascii.isWhitespace(self.current_char.?)) {
                self.skipWhitespace();
                continue;
            }

            if (std.ascii.isDigit(self.current_char.?)) {
                const num = self.integer() catch return TokenError.InvalidType;
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

    pub fn eat(self: *Interpreter, token_type: TType) !void {
        if (self.current_token.Type == token_type) {
            var curr = try self.getNextToken();
            self.current_token = &curr;
        } else {
            std.debug.print("{any}, {any}\n", .{ self.current_token.Type, token_type });
            return TokenError.InvalidType;
        }
    }

    pub fn expr(self: *Interpreter) !u8 {
        var result: u8 = undefined;

        var curr = try self.getNextToken();

        self.current_token = &curr;

        var left = self.current_token.*;
        try self.eat(TType.INTEGER);

        while (self.current_token.Type != TType.EOF) {
            const op = self.current_token.*;
            if (op.Type == TType.PLUS) {
                try self.eat(TType.PLUS);
            } else if (op.Type == TType.MULTI) {
                try self.eat(TType.MULTI);
            } else if (op.Type == TType.DIVIS) {
                try self.eat(TType.DIVIS);
            } else {
                try self.eat(TType.MINUS);
            }

            const right = self.current_token.*;
            try self.eat(TType.INTEGER);

            if (op.Type == TType.PLUS) {
                result = left.value + right.value;
            } else if (op.Type == TType.MINUS) {
                result = left.value - right.value;
            } else if (op.Type == TType.MULTI) {
                result = left.value * right.value;
            } else {
                result = left.value / right.value;
            }
            left = Token.init(TType.INTEGER, result);
        }

        return result;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    //const allocator = gpa.allocator();

    const text = "10 * 25 + 5";
    var int = Interpreter.init(text);

    const result = try int.expr();
    std.debug.print("{d}\n", .{result});
}
