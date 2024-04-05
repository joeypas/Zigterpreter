const std = @import("std");
const Allocator = std.mem.Allocator;

// Token Types
pub const TType = enum {
    INTEGER,
    PLUS,
    MINUS,
    MULTI,
    DIVIS,
    EOF,
    LPAREN,
    RPAREN,
    BEGIN,
    END,
    DOT,
    ASSIGN,
    SEMI,
    ID,
};

// Type to hold either a character or a number
pub const CharNum = union(enum) {
    Char: u8,
    Num: i128,
    Str: []const u8,
};

// Struct to hold the token type and the value
pub const Token = struct {
    Type: TType,
    value: CharNum,

    pub fn init(Ty: TType, val: CharNum) Token {
        return Token{
            .Type = Ty,
            .value = val,
        };
    }

    pub fn str(self: Token, allocator: Allocator) std.fmt.AllocPrintError![]u8 {
        switch (self.value) {
            .Num => |num| return std.fmt.allocPrint(allocator, "Token({s}, {d})", .{ @tagName(self.Type), num }),
            .Char => |char| return std.fmt.allocPrint(allocator, "Token({s}, {c})", .{ @tagName(self.Type), char }),
            .Str => |st| return std.fmt.allocPrint(allocator, "Token({s}, {s})", .{ @tagName(self.Type), st }),
        }
    }
};

// Error Types
pub const TokenError = error{ InvalidToken, InvalidCharacter, InvalidType, Mem };
