const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Tokenizer = @import("shell_tokenizer.zig");
const Token = Tokenizer.Token;
const TType = Tokenizer.TType;
const TokenError = Tokenizer.TokenError;
const Lexer = Tokenizer.Lexer;
const ReservedWords = Tokenizer.Reserved;
const getAllTokens = Tokenizer.getAllTokens;

const ReducedTypes = enum {
    program,
    complete_commands,
    complete_command,
    list,
    and_or,
    pipeline,
    pipe_sequence,
    command,
    compound_command,
    subshell,
    compound_list,
    term,
    for_clause,
    name,
    in,
    wordlist,
    case_clause,
    case_item,
    pattern,
    if_clause,
    else_part,
    while_clause,
    until_clause,
    function_definition,
    function_body,
    fname,
    brace_group,
    do_group,
    simple_command,
    cmd_name,
    cmd_word,
    cmd_prefix,
    cmd_suffix,
    redirect_list,
    io_redirect,
    io_file,
    filename,
    io_here,
    here_end,
    newline_list,
    linebreak,
    sparator_op,
    separator,
    operator,
    reserved,
};

const Side = enum {
    LEFT,
    RIGHT,
};

const TreeErr = error{ BranchTaken, Memory, NotExist, NoCurr };

// This is a mess
pub fn Tree(comptime Child: type) type {
    return struct {
        const This = @This();
        const Node = struct {
            Type: ReducedTypes,
            left: ?*Node,
            right: ?*Node,
            parent: ?*Node,
            child: ?Child,
        };

        head: ?*Node,
        curr: ?*Node,
        allocator: Allocator,

        pub fn init(allocator: Allocator) This {
            return This{
                .head = null,
                .curr = null,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *This) void {
            self.curr = self.head.?;
            self.deleter();
            self.allocator.destroy(self.head.?);
        }

        fn deleter(self: *This) void {
            if (self.curr) |current| {
                if (current.right) |right| {
                    self.curr = right;
                    self.deleter();
                } else if (current.left) |left| {
                    self.curr = left;
                    self.deleter();
                } else {
                    if (current.parent) |parent| {
                        if (parent.right) |right| {
                            self.allocator.destroy(right);
                            parent.right = null;
                        } else if (parent.left) |left| {
                            self.allocator.destroy(left);
                            parent.left = null;
                        }

                        self.curr = parent;

                        self.deleter();
                    }
                }
            }
        }

        pub fn addChild(self: *This, t: ReducedTypes, child: ?Child, side: Side) TreeErr!void {
            if (self.head != null) {
                if (self.curr) |current| {
                    switch (side) {
                        .LEFT => {
                            if (current.left != null) {
                                return TreeErr.BranchTaken;
                            }
                            const node = self.allocator.create(Node) catch return TreeErr.Memory;
                            node.* = .{ .Type = t, .left = null, .right = null, .child = child, .parent = current };

                            current.left = node;
                        },
                        .RIGHT => {
                            if (current.right != null) {
                                return TreeErr.BranchTaken;
                            }
                            const node = self.allocator.create(Node) catch return TreeErr.Memory;
                            node.* = .{ .Type = t, .left = null, .right = null, .child = child, .parent = current };

                            current.right = node;
                        },
                    }
                } else {
                    unreachable;
                }
            } else {
                const node = self.allocator.create(Node) catch return TreeErr.Memory;
                node.* = .{ .Type = t, .left = null, .right = null, .child = child, .parent = null };
                self.head = node;
                self.curr = node;
            }
        }

        pub fn visitBranch(self: *This, side: Side) TreeErr!void {
            if (self.curr) |current| {
                switch (side) {
                    .LEFT => {
                        if (current.left) |left| {
                            self.curr = left;
                        } else {
                            return TreeErr.NotExist;
                        }
                    },
                    .RIGHT => {
                        if (current.right) |right| {
                            self.curr = right;
                        }
                    },
                }
            } else {
                return TreeErr.NoCurr;
            }
        }

        pub fn visitParent(self: *This) TreeErr!void {
            if (self.curr) |current| {
                if (current.parent) |parent| self.curr = parent else return TreeErr.NotExist;
            } else {
                return TreeErr.NoCurr;
            }
        }

        pub fn branchExists(self: *This, side: Side) bool {
            if (self.curr) |current| {
                switch (side) {
                    .LEFT => {
                        if (current.left != null) return true //
                        else return false;
                    },
                    .RIGHT => {
                        if (current.right != null) return true //
                        else return false;
                    },
                }
            } else {
                return false;
            }
        }

        pub fn bottom(self: *This) void {
            var temp = self.head;
            while (temp.?.left != null) {
                temp = temp.?.left;
            }
            self.curr = temp.?;
        }

        pub fn next(self: *This) ?Node {
            if (self.curr) |current| {
                if (current.right) |right| {
                    const ret = right.*;
                    self.allocator.destroy(right);
                    current.right = null;
                    return ret;
                } else {
                    const ret = current.*;
                    if (current.parent) |parent| {
                        self.curr = parent;
                        self.allocator.destroy(current);
                        self.curr.?.left = null;
                    }
                    return ret;
                }
            }
            return null;
        }
    };
}

test "tree" {
    const allocator = std.testing.allocator;
    var tree = Tree(Token).init(allocator);
    defer tree.deinit();
    try tree.addChild(.program, null, .LEFT);

    const tok = Token.init(.WORD, .{ .Num = 1 });
    try tree.addChild(.cmd_name, tok, .LEFT);

    const tok2 = Token.init(.WORD, .{ .Num = 2 });
    try tree.addChild(.cmd_word, tok2, .RIGHT);
    //std.debug.print("{any}\n\n", .{tree.curr.?.Type});

    try tree.visitBranch(.LEFT);
    //std.debug.print("{any}\n\n", .{tree.curr.?.Type});

    try tree.visitParent();
    try tree.visitBranch(.RIGHT);
    //std.debug.print("{any}\n\n", .{tree.curr.?.Type});

    const tok3 = Token.init(.WORD, .{ .Num = 3 });
    try tree.addChild(.cmd_prefix, tok3, .LEFT);
    try tree.addChild(.cmd_suffix, tok3, .RIGHT);
    try tree.visitBranch(.LEFT);

    //std.debug.print("{any}\n\n", .{tree.curr.?.Type});
    try tree.visitParent();
    try tree.visitBranch(.RIGHT);
    //std.debug.print("{any}\n", .{tree.curr.?.Type});
}

pub const AST = struct {
    tree: Tree(Token),
    allocator: Allocator,
    tokens: []const Token,
    index: usize,
    depth: usize,

    pub fn init(allocator: Allocator, tokens: []const Token) AST {
        return AST{ .tree = Tree(Token).init(allocator), .allocator = allocator, .tokens = tokens, .index = 0, .depth = 0 };
    }

    pub fn deinit(self: *AST) void {
        self.tree.deinit();
    }

    fn consume(self: *AST, t: ReducedTypes, token: ?Token, side: Side) TreeErr!void {
        if (token) |tok| {
            self.index += 1;
            while (self.tree.branchExists(side)) {
                try self.tree.visitBranch(side);
                self.depth += 1;
            }
            try self.tree.addChild(t, tok, side);
            try self.tree.visitBranch(side);
            self.depth += 1;
        } else {
            while (self.tree.branchExists(side)) {
                try self.tree.visitBranch(side);
                self.depth += 1;
            }
            try self.tree.addChild(t, null, side);
            try self.tree.visitBranch(side);
            self.depth += 1;
        }
    }

    fn parseCompleteCommand(self: *AST) TreeErr!void {
        try self.tree.addChild(.complete_command, null, .LEFT);
        while (self.index < self.tokens.len) {
            switch (self.tokens[self.index].Type) {
                .AND, .SEMI => {
                    try self.consume(.separator, self.tokens[self.index], .RIGHT);
                    try self.parseList();
                },
                else => {
                    try self.consume(.list, null, .LEFT);
                    try self.parseList();
                },
            }
        }
    }

    fn parseList(self: *AST) TreeErr!void {
        while (self.index < self.tokens.len) {
            switch (self.tokens[self.index].Type) {
                .AND, .SEMI => {
                    try self.consume(.and_or, self.tokens[self.index], .RIGHT);
                    try self.parseAndOr();
                },
                else => {
                    try self.consume(.and_or, null, .LEFT);
                    try self.parseAndOr();
                },
            }
        }
    }

    fn parseAndOr(self: *AST) TreeErr!void {
        while (self.index < self.tokens.len) {
            switch (self.tokens[self.index].Type) {
                .AND_IF, .OR_IF => {
                    try self.consume(.pipeline, self.tokens[self.index], .RIGHT);
                    try self.parsePipeline();
                },
                else => {
                    try self.consume(.pipeline, null, .LEFT);
                    try self.parsePipeline();
                },
            }
        }
    }

    fn parsePipeline(self: *AST) TreeErr!void {
        while (self.index < self.tokens.len) {
            switch (self.tokens[self.index].Type) {
                .BANG => {
                    try self.consume(.reserved, self.tokens[self.index], .LEFT);
                    try self.tree.visitParent();
                    try self.consume(.pipe_sequence, null, .RIGHT);
                    try self.parsePipeSeq();
                },
                else => {
                    try self.consume(.pipe_sequence, null, .LEFT);
                    try self.parsePipeSeq();
                },
            }
        }
    }

    fn parsePipeSeq(self: *AST) TreeErr!void {
        while (self.index < self.tokens.len) {
            switch (self.tokens[self.index].Type) {
                .PIPE => {
                    try self.consume(.command, self.tokens[self.index], .RIGHT);
                    try self.parseCommand();
                },
                else => {
                    try self.consume(.command, null, .LEFT);
                    try self.parseCommand();
                },
            }
        }
    }

    fn parseCommand(self: *AST) TreeErr!void {
        while (self.index < self.tokens.len) {
            switch (self.tokens[self.index].Type) {
                .LPAREN, .LBRACE, .FOR, .CASE, .WHILE, .UNTIL => {
                    try self.consume(.compound_command, null, .LEFT);
                    try self.parseCompoundCommand();
                },
                .WORD => {
                    if (self.index + 1 < self.tokens.len) {
                        switch (self.tokens[self.index + 1].Type) {
                            .LPAREN => {
                                try self.consume(.function_definition, null, .LEFT);
                                //try self.parseFunctionDefinition();
                            },
                            else => {
                                try self.consume(.simple_command, null, .LEFT);
                                try self.parseSimpleCommand();
                            },
                        }
                    } else {
                        try self.consume(.simple_command, null, .LEFT);
                        try self.parseSimpleCommand();
                    }
                },
                else => {
                    try self.consume(.redirect_list, null, .RIGHT);
                    //try self.parseRedirectList();
                },
            }
        }
    }

    fn parseCompoundCommand(self: *AST) !void {
        while (self.index < self.tokens.len) {
            switch (self.tokens[self.index].Type) {
                .LPAREN => {
                    try self.consume(.subshell, null, .LEFT);
                },
                else => {},
            }
        }
    }

    fn parseSimpleCommand(self: *AST) TreeErr!void {
        while (self.index < self.tokens.len) {
            switch (self.tokens[self.index].Type) {
                .WORD => {
                    if (self.tree.branchExists(.LEFT)) {
                        //std.debug.print("cmd_suffix: {s}\n", .{self.tokens[self.index].value.Str});
                        try self.consume(.cmd_suffix, self.tokens[self.index], .RIGHT);
                        try self.tree.visitParent();
                        self.depth -= 1;
                    } else {
                        //std.debug.print("cmd_name: {s}\n", .{self.tokens[self.index].value.Str});
                        try self.consume(.cmd_name, self.tokens[self.index], .LEFT);
                        try self.tree.visitParent();
                        self.depth -= 1;
                    }
                },
                else => {
                    //var temp = self.depth;
                    //std.debug.print("{d}\n", .{self.depth});
                    for (1..self.depth) |i| {
                        try self.tree.visitParent();
                        _ = i;
                        //temp -= 1;
                    }
                    self.depth = 1;
                    //std.debug.print("{any}\n", .{self.tree.curr.?.Type});
                    self.parseList() catch std.debug.print("FAIl\n", .{});
                },
            }
        }
    }

    pub fn parse(self: *AST) !void {
        try self.parseCompleteCommand();
    }
};

test "parse 2 commands" {
    const allocator = std.testing.allocator;

    const line = "ls test; echo hello; ls an; echo two";

    var lex = try Lexer.init(line, allocator);
    defer lex.deinit();

    var list = try getAllTokens(allocator, &lex);
    defer list.deinit();

    var ast = AST.init(allocator, list.items);
    defer ast.deinit();

    try ast.parse();
    try std.testing.expect(ast.tree.head.?.Type == .complete_command);
    try std.testing.expect(ast.tree.curr.?.Type == .simple_command);
    ast.tree.bottom();
    const node = ast.tree.next();
    try std.testing.expect(std.mem.eql(u8, node.?.child.?.value.Str, "ls"));
    const node2 = ast.tree.next();
    try std.testing.expect(std.mem.eql(u8, node2.?.child.?.value.Str, "test"));
    //var p = ast.tree.head.?;

}
