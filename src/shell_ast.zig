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
            std.debug.print("Deleted head\n", .{});
        }

        fn deleter(self: *This) void {
            if (self.curr) |current| {
                if (self.curr.?.right) |right| {
                    self.curr = right;
                    self.deleter();
                } else {
                    if (current.left) |left| {
                        self.curr = left;
                        self.deleter();
                    } else {
                        if (current.parent) |parent| {
                            if (parent.right) |right| {
                                self.allocator.destroy(right);
                                std.debug.print("Deleted right\n", .{});
                                parent.right = null;
                            }

                            if (parent.left) |left| {
                                self.allocator.destroy(left);
                                std.debug.print("Deleted left\n", .{});
                                parent.left = null;
                            }
                            self.curr = parent;
                            self.deleter();
                        }
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
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var tree = Tree(Token).init(allocator);
    defer tree.deinit();
    try tree.addChild(.program, null, .LEFT);

    const tok = Token.init(.WORD, .{ .Num = 1 });
    try tree.addChild(.cmd_name, tok, .LEFT);

    const tok2 = Token.init(.WORD, .{ .Num = 2 });
    try tree.addChild(.cmd_word, tok2, .RIGHT);
    std.debug.print("{any}\n\n", .{tree.curr.?.Type});

    try tree.visitBranch(.LEFT);
    std.debug.print("{any}\n\n", .{tree.curr.?.Type});

    try tree.visitParent();
    try tree.visitBranch(.RIGHT);
    std.debug.print("{any}\n\n", .{tree.curr.?.Type});

    const tok3 = Token.init(.WORD, .{ .Num = 3 });
    try tree.addChild(.cmd_prefix, tok3, .LEFT);
    try tree.addChild(.cmd_suffix, tok3, .RIGHT);
    try tree.visitBranch(.LEFT);

    std.debug.print("{any}\n\n", .{tree.curr.?.Type});
    try tree.visitParent();
    try tree.visitBranch(.RIGHT);
    std.debug.print("{any}\n", .{tree.curr.?.Type});
}

pub const AST = struct {
    tree: Tree(Token),
    allocator: Allocator,
    tokens: []const Token,
    index: usize,

    pub fn init(allocator: Allocator, tokens: []const Token) AST {
        return AST{
            .tree = Tree(Token).init(allocator),
            .allocator = allocator,
            .tokens = tokens,
            .index = 0,
        };
    }

    pub fn deinit(self: *AST) void {
        self.tree.deinit();
    }
};
