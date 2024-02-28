const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub const TType = enum {
    WORD,
    ASSIGNMENT_WORD,
    NAME,
    NEWLINE,
    IO_NUMBER,
    AND_IF,
    OR_IF,
    DSEMI,
    DLESS,
    DGREAT,
    LESSAND,
    GREATAND,
    LESSGREAT,
    DLESSDASH,
    CLOBBER,
    IF,
    THEN,
    ELSE,
    ELIF,
    FI,
    DO,
    DONE,
    CASE,
    ESAC,
    WHILE,
    UNTIL,
    FOR,
    LBRACE,
    RBRACE,
    BANG,
    IN,
    PIPE,
    AND,
    OR,
    SEMI,
    LPAREN,
    RPAREN,
    LESS,
    GREATER,
    EQUAL,
    QUOTE,
    DQUOTE,
    EOF,
};

pub const Reserved = enum {
    IF,
    THEN,
    ELSE,
    ELIF,
    FI,
    DO,
    DONE,
    CASE,
    ESAC,
    WHILE,
    UNTIL,
    FOR,
};

// Type to hold either a character or a number
const DataType = union(enum) {
    Char: u8,
    Num: i128,
    Str: []u8,
    Word: Reserved,
};

// Struct to hold the token type and the value
pub const Token = struct {
    Type: TType,
    value: DataType,

    pub fn init(Ty: TType, val: DataType) Token {
        return Token{
            .Type = Ty,
            .value = val,
        };
    }

    pub fn str(self: Token, allocator: Allocator) std.fmt.AllocPrintError![]u8 {
        switch (self.value) {
            .Num => |num| return std.fmt.allocPrint(allocator, "Token({s}, {d})", .{ @tagName(self.Type), num }),
            .Char => |char| {
                if (std.ascii.isControl(char)) {
                    return std.fmt.allocPrint(allocator, "Token({s}, '\\n')", .{@tagName(self.Type)});
                }
                return std.fmt.allocPrint(allocator, "Token({s}, {c})", .{ @tagName(self.Type), char });
            },
            .Str => |s| return std.fmt.allocPrint(allocator, "Token({s}, {s})", .{ @tagName(self.Type), s }),
            .Word => |w| return std.fmt.allocPrint(allocator, "Token({s}, {s})", .{ @tagName(self.Type), @tagName(w) }),
        }
    }
};

// Error Types
pub const TokenError = error{ InvalidToken, InvalidCharacter, InvalidType, Mem };

pub const Lexer = struct {
    text: []const u8,
    pos: usize,
    current_char: ?u8,
    allocator: Allocator,
    strs: ArrayList([]const u8),

    // Initialize the lexer with the input string
    pub fn init(text: []const u8, alloc: Allocator) !Lexer {
        return Lexer{
            .text = text,
            .allocator = alloc,
            .pos = 0,
            .current_char = text[0],
            .strs = ArrayList([]const u8).init(alloc),
        };
    }

    pub fn deinit(self: *Lexer) void {
        for (self.strs.items) |s| {
            self.allocator.free(s);
        }
        self.strs.deinit();
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
        while (self.current_char != null and std.ascii.isWhitespace(self.current_char.?) and !std.ascii.isControl(self.current_char.?)) {
            self.advance();
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

    fn str(self: *Lexer) !ArrayList(u8) {
        var string = ArrayList(u8).init(self.allocator);

        self.advance();

        while (self.current_char != null and self.current_char.? != '"') {
            try string.append(self.current_char.?);
            self.advance();
        }
        self.advance();
        return string;
    }

    fn word(self: *Lexer) !ArrayList(u8) {
        var string = ArrayList(u8).init(self.allocator);

        while (self.current_char != null and std.ascii.isAlphabetic(self.current_char.?) or self.current_char == '_') {
            try string.append(self.current_char.?);
            self.advance();
        }

        return string;
    }

    // Get the next token
    pub fn getNextToken(self: *Lexer) TokenError!Token {
        while (self.current_char != null) {
            if (std.ascii.isWhitespace(self.current_char.?) and !std.ascii.isControl(self.current_char.?)) {
                self.skipWhitespace();
                continue;
            }

            if (std.ascii.isDigit(self.current_char.?)) {
                const num = self.integer() catch return TokenError.InvalidCharacter;
                return Token.init(TType.IO_NUMBER, .{ .Num = num });
            }

            if (self.current_char == '"') {
                const s = self.str() catch return TokenError.Mem;
                defer s.deinit();
                const st = std.fmt.allocPrint(self.allocator, "{s}", .{s.items}) catch return TokenError.Mem;
                self.strs.append(st) catch return TokenError.Mem;
                return Token.init(TType.WORD, .{ .Str = st });
            }

            if (self.current_char == '&') {
                self.advance();
                if (self.current_char == '&') {
                    self.advance();
                    return Token.init(TType.AND_IF, .{ .Char = '&' });
                }
                return Token.init(TType.AND, .{ .Char = '&' });
            }

            if (self.current_char == '(') {
                self.advance();
                return Token.init(TType.LPAREN, .{ .Char = '(' });
            }

            if (self.current_char == ')') {
                self.advance();
                return Token.init(TType.RPAREN, .{ .Char = ')' });
            }

            if (self.current_char == '<') {
                self.advance();
                if (self.current_char == '<') {
                    self.advance();
                    if (self.current_char == '-') {
                        self.advance();
                        return Token.init(TType.DLESSDASH, .{ .Char = '<' });
                    }
                    return Token.init(TType.DLESS, .{ .Char = '<' });
                } else if (self.current_char == '>') {
                    self.advance();
                    return Token.init(TType.LESSGREAT, .{ .Char = '<' });
                } else if (self.current_char == '&') {
                    self.advance();
                    return Token.init(TType.LESSAND, .{ .Char = '<' });
                }
                return Token.init(TType.LESS, .{ .Char = '<' });
            }

            if (self.current_char == '>') {
                self.advance();
                if (self.current_char == '>') {
                    self.advance();
                    return Token.init(TType.DGREAT, .{ .Char = '>' });
                } else if (self.current_char == '&') {
                    self.advance();
                    return Token.init(TType.GREATAND, .{ .Char = '>' });
                } else if (self.current_char == '|') {
                    self.advance();
                    return Token.init(TType.CLOBBER, .{ .Char = '>' });
                }
                return Token.init(TType.GREATER, .{ .Char = '>' });
            }

            if (self.current_char == ';') {
                self.advance();
                return Token.init(TType.SEMI, .{ .Char = ';' });
            }

            if (self.current_char == '|') {
                self.advance();
                if (self.current_char == '|') {
                    self.advance();
                    return Token.init(TType.OR_IF, .{ .Char = '|' });
                }
                return Token.init(TType.PIPE, .{ .Char = '|' });
            }

            if (std.ascii.isControl(self.current_char.?)) {
                self.advance();
                return Token.init(TType.NEWLINE, .{ .Char = '\n' });
            }

            if (std.ascii.isAlphabetic(self.current_char.?)) {
                const w = self.word() catch return TokenError.InvalidCharacter;
                defer w.deinit();
                const wo = std.fmt.allocPrint(self.allocator, "{s}", .{w.items}) catch return TokenError.Mem;
                self.strs.append(wo) catch return TokenError.Mem;

                if (std.mem.eql(u8, wo, "if")) return Token.init(TType.IF, .{ .Word = .IF });
                if (std.mem.eql(u8, wo, "then")) return Token.init(TType.THEN, .{ .Word = .THEN });
                if (std.mem.eql(u8, wo, "else")) return Token.init(TType.ELSE, .{ .Word = .ELSE });
                if (std.mem.eql(u8, wo, "elif")) return Token.init(TType.ELIF, .{ .Word = .ELIF });
                if (std.mem.eql(u8, wo, "fi")) return Token.init(TType.FI, .{ .Word = .FI });
                if (std.mem.eql(u8, wo, "do")) return Token.init(TType.DO, .{ .Word = .DO });
                if (std.mem.eql(u8, wo, "done")) return Token.init(TType.DONE, .{ .Word = .DONE });
                if (std.mem.eql(u8, wo, "case")) return Token.init(TType.CASE, .{ .Word = .CASE });
                if (std.mem.eql(u8, wo, "esac")) return Token.init(TType.ESAC, .{ .Word = .ESAC });
                if (std.mem.eql(u8, wo, "while")) return Token.init(TType.WHILE, .{ .Word = .WHILE });
                if (std.mem.eql(u8, wo, "until")) return Token.init(TType.UNTIL, .{ .Word = .UNTIL });
                if (std.mem.eql(u8, wo, "for")) return Token.init(TType.FOR, .{ .Word = .FOR });

                if (std.ascii.isWhitespace(self.current_char orelse ' ')) {
                    self.skipWhitespace();
                }
                if (self.current_char == '=') {
                    self.advance();
                    return Token.init(TType.ASSIGNMENT_WORD, .{ .Str = wo });
                }
                return Token.init(TType.WORD, .{ .Str = wo });
            }

            return TokenError.InvalidToken;
        }

        return Token.init(TType.EOF, undefined);
    }
};

pub fn getAllTokens(allocator: Allocator, lex: *Lexer) !ArrayList(Token) {
    var list = ArrayList(Token).init(allocator);

    var curr = try lex.getNextToken();

    while (curr.Type != TType.EOF) {
        try list.append(curr);
        curr = try lex.getNextToken();
    }

    return list;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const string = "ls test > test";
    var lex = try Lexer.init(string, allocator);
    defer lex.deinit();

    var list = try getAllTokens(allocator, &lex);
    defer list.deinit();

    for (list.items) |item| {
        switch (item.Type) {
            .WORD => {
                _ = std.process.execv(allocator, &([_][]const u8{item.value.Str})) catch return;
            },
            else => {
                continue;
            },
        }
    }
}

test {
    const string = "ls test > test";
    var lex = try Lexer.init(string, std.testing.allocator);
    defer lex.deinit();

    var list = try getAllTokens(std.testing.allocator, &lex);
    defer list.deinit();

    std.debug.print("\n", .{});

    for (list.items) |item| {
        const str = try item.str(std.testing.allocator);
        defer std.testing.allocator.free(str);
        std.debug.print("{s}\n", .{str});
    }
}
