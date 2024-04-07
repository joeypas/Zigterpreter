const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const types = @import("types.zig");

const Token = types.Token;
const TType = types.TType;
const TokenError = types.TokenError;
const CharNum = types.CharNum;

// LEXER CODE
// The lexer takes in a string and returns a list of tokens
pub const Lexer = struct {
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
