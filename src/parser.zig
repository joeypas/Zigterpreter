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
const Lexer = @import("lexer.zig").Lexer;

// PARSER CODE
// The parser takes in a list of tokens and returns an abstract syntax tree
pub const Parser = struct {
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
