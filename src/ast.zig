const std = @import("std");
const types = @import("types.zig");
const Token = types.Token;
const TType = types.TType;
const TokenError = types.TokenError;
const CharNum = types.CharNum;

pub const TreeType = enum { BinOp, Num, UnaryOp };

pub const AST = union(TreeType) {
    BinOp: struct {
        left: *AST,
        token: Token,
        right: *AST,
    },
    Num: struct {
        token: Token,
    },
    UnaryOp: struct { token: Token, expr: *AST },

    pub fn visit(self: AST) i128 {
        switch (self) {
            .BinOp => |tok| {
                switch (tok.token.Type) {
                    .PLUS => {
                        return tok.left.visit() + tok.right.visit();
                    },
                    .MINUS => {
                        return tok.left.visit() - tok.right.visit();
                    },
                    .MULTI => {
                        return tok.left.visit() * tok.right.visit();
                    },
                    .DIVIS => {
                        return @divTrunc(tok.left.visit(), tok.right.visit());
                    },
                    else => unreachable,
                }
            },
            .Num => |tok| {
                switch (tok.token.value) {
                    .Num => return tok.token.value.Num,
                    .Char => unreachable,
                    .Str => unreachable,
                }
                return tok.token.value.Num;
            },
            .UnaryOp => |tok| {
                const op = tok.token.Type;

                switch (op) {
                    .PLUS => {
                        return tok.expr.visit();
                    },
                    .MINUS => {
                        return 0 - tok.expr.visit();
                    },
                    else => unreachable,
                }
            },
        }
    }
};
