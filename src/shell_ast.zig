const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Tokenizer = @import("shell_tokenizer.zig");
const Token = Tokenizer.Token;
const TType = Tokenizer.TokenType;
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

const TreeNode = struct {
    Type: ReducedTypes,
    children: ArrayList(*TreeNode),
    token: ?Token,
    allocator: Allocator,

    pub fn init(allocator: *Allocator, Type: ReducedTypes, token: ?Token) TreeNode {
        return TreeNode{
            .Type = Type,
            .children = ArrayList(*TreeNode).init(allocator),
            .token = token,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TreeNode) void {
        for (self.children.items) |child| {
            child.deinit();
            self.allocator.destroy(child);
        }
        self.children.deinit();
    }
};

const AST = struct {
    head: *TreeNode,
    allocator: Allocator,
    tokens: []const Token,
    index: usize,

    pub fn init(allocator: Allocator, tokens: []const Token) AST {
        return AST{
            .head = undefined,
            .allocator = allocator,
            .tokens = tokens,
            .index = 0,
        };
    }

    fn reduceProgram(self: *AST) !*TreeNode {
        //var node = TreeNode.init(self.allocator, .program, null);

        while (self.index < self.tokens.len) : (self.index += 1) {
            //var child = self.reduceCompleteCommands();

        }
    }

    fn parseCompleteCommands(self: *AST) !*TreeNode {
        const node = try self.allocator.create(TreeNode);
        node.init(self.allocator, .complete_commands, null);
        while (self.index < self.tokens.len - 1) : (self.index += 1) {
            const cc = try self.parseCompleteCommandCommand();
            try node.children.append(cc);
            if (self.tokens[self.idnex + 1].Type == .NEWLINE) {
                self.index += 1;
                const nl = try self.parseNewLines();
                try node.children.append(nl);
            }
        }
        const cc = try self.parseCompleteCommand();
        try node.children.append(cc);
        return node;
    }

    fn parseCompleteCommand(self: *AST) !*TreeNode {
        const node = try self.allocator.create(TreeNode);
        node.init(self.allocator, .complete_command, null);
        const list = try self.parseList();
        try node.children.append(list);
        self.index += 1;
        if (self.index < self.tokens.len) {
            const sep = try self.parseSeperatorOp();
            try node.children.append(sep);
        }

        return node;
    }

    fn parseList(self: *AST) !*TreeNode {
        const node = try self.allocator.create(TreeNode);
        node.init(self.allocator, .list, null);

        while (true) {
            const and_or = try self.parseAndOr();
            try node.children.append(and_or);
            if (self.tokens[self.index + 1].Type == .AND or self.tokens[self.index + 1].Type == .SEMI) {
                self.index += 1;
                const sep = try self.parseSeperatorOp();
                try node.children.append(sep);
            } else {
                break;
            }
        }

        return node;
    }

    fn parseAndOr(self: *AST) !*TreeNode {
        const node = try self.allocator.create(TreeNode);
        node.init(self.allocator, .and_or, null);

        while (true) {
            const pipe_line = try self.parsePipeLine();
            try node.children.append(pipe_line);
            if (self.tokens[self.index + 1].Type == .OR or self.tokens[self.index + 1].Type == .AND) {
                self.index += 1;
                const sep = try self.parseSeperatorOp();
                try node.children.append(sep);
            } else {
                break;
            }
        }

        return node;
    }

    fn parsePipeLine(self: *AST) !*TreeNode {
        const node = try self.allocator.create(TreeNode);
        node.init(self.allocator, .pipeline, null);

        while (true) {
            const pipe_seq = try self.parsePipeSequence();
            try node.children.append(pipe_seq);
            if (self.tokens[self.index + 1].Type == .PIPE) {
                self.index += 1;
                const sep = try self.parseSeperatorOp();
                try node.children.append(sep);
            } else {
                break;
            }
        }

        return node;
    }

    fn parsePipeSequence(self: *AST) !*TreeNode {
        const node = try self.allocator.create(TreeNode);
        node.init(self.allocator, .pipe_sequence, null);

        while (true) {
            const cmd = try self.parseCommand();
            try node.children.append(cmd);
            if (self.tokens[self.index + 1].Type == .PIPE) {
                self.index += 1;
                const sep = try self.parseSeperatorOp();
                try node.children.append(sep);
            } else {
                break;
            }
        }

        return node;
    }

    fn parseCommand(self: *AST) !*TreeNode {
        const node = try self.allocator.create(TreeNode);
        node.init(self.allocator, .command, null);

        if (self.tokens[self.index + 1].Type == .LBRACE) {
            const comp_cmd = try self.parseCompoundCommand();
            try node.children.append(comp_cmd);
        } else {
            const simple_cmd = try self.parseSimpleCommand();
            try node.children.append(simple_cmd);
        }
        return node;
    }

    fn parseSimpleCommand(self: *AST) !*TreeNode {
        const node = try self.allocator.create(TreeNode);
        node.init(self.allocator, .simple_command, null);

        const cmd_name = try self.parseCmdName();
        try node.children.append(cmd_name);

        while (self.tokens[self.index + 1].Type != .NEWLINE) {
            const cmd_word = try self.parseCmdWord();
            try node.children.append(cmd_word);
        }

        return node;
    }

    fn parseNewLines(self: *AST) !*TreeNode {
        var size: usize = 0;
        while (self.index < self.tokens.len and self.tokens[self.index].Type == TType.NEWLINE) : (self.index += 1) {
            size += 1;
        }
        var ret = try self.allocator.create(TreeNode);
        ret.init(self.allocator, .newline_list, self.tokens[self.index - 1]);
        return ret;
    }

    fn parseIOFile(self: *AST) TreeNode {
        var node = TreeNode.init(self.allocator, .io_file, self.tokens[self.index]);
        self.index += 1;
        try node.children.append(&TreeNode.init(self.allocator, .filename, self.tokens[self.index]));
        self.index += 1;

        return node;
    }
};
