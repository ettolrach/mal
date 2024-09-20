const std = @import("std");

const reader = @import("reader.zig");
const printer = @import("printer.zig");
const getline = @import("readline.zig").getline;
const hash_map = @import("hmap.zig");

const Allocator = @import("std").heap.c_allocator;

const MalType = @import("types.zig").MalType;
const MalError = @import("error.zig").MalError;
const MalLinkedList = @import("linked_list.zig").MalLinkedList;
const get_error_data = @import("error.zig").get_error_data;
const throw = @import("error.zig").throw;
const stdout_file = std.io.getStdOut();

var repl_environment = hash_map.MalHashMap { };

fn READ(a: []const u8) !*MalType {
    var read = try reader.read_str(a);
    return reader.read_form(&read);
}

fn EVAL(mal: *MalType, env: hash_map.MalHashMap) MalError!*MalType {

    //  try stdout_file.writeAll("EVAL: ");
    //  try PRINT(mal.*);

    switch(mal.*) {
        .List => |ll| {
            const items = ll.data.items;
            if(items.len == 0) {
                mal.incref();
                return mal;
            }
            else {
                const first_mal = items[0];
                const evaluated_first = try EVAL(first_mal, env);
                defer evaluated_first.decref();
                // A slice would be sufficient, but a List is convenient
                // for partial deallocation in case of error.
                const args = try MalType.new_list();
                defer args.decref();
                for(items[1..]) |x| {
                    const new_item = try EVAL(x, env);
                    try args.List.data.append(Allocator, new_item);
                }
                return apply_function(evaluated_first.*, args.List.data.items);
            }
        },
        .Symbol => {
            return EVAL_symbol(mal, env);
        },
        .Vector => |ll| {
            return EVAL_vector(ll.data.items, env);
        },
        .HashMap => |hmap| {
            return EVAL_map(hmap.data, env);
        },
        else => {
            mal.incref();
            return mal;
        },
    }
}

fn PRINT(mal: MalType) !void {
    try printer.one_stdout(mal);
    try stdout_file.writeAll("\n");
}

fn rep(input: []const u8) !void {
    const read_input = try READ(input);
    defer read_input.decref();
    const eval_input = try EVAL(read_input, repl_environment);
    defer eval_input.decref();
    try PRINT(eval_input.*);
}

fn EVAL_symbol(mal: *MalType, env: hash_map.MalHashMap) !*MalType {
    if(env.get(mal)) |value| {
        value.incref();
        return value;
    }
    const err = try std.fmt.allocPrint(Allocator, "'{s}' not found",
        .{mal.Symbol.data});
    return throw(try MalType.new_string(err, false));
}

fn EVAL_vector(ll: []*MalType, env: hash_map.MalHashMap) !*MalType {
            const ret_mal = try MalType.new_vector();
            errdefer ret_mal.decref();
            for(ll) |x| {
                const new_mal = try EVAL(x, env);
                try ret_mal.Vector.data.append(Allocator, new_mal);
            }
            return ret_mal;
}

fn EVAL_map(hmap: hash_map.MalHashMap, env: hash_map.MalHashMap) !*MalType {
            const new_hashmap = try MalType.new_hashmap();
            errdefer new_hashmap.decref();
            var iterator = hmap.iterator();
            while(iterator.next()) |pair| {
                const key = pair.key_ptr.*;
                const value = pair.value_ptr.*;
                const evaled_value = try EVAL(value, env);
                // key *is* new in this map.
                try hash_map.map_insert_incref_key(&new_hashmap.HashMap.data, key, evaled_value);
            }
            return new_hashmap;
}

const safeAdd = @import("std").math.add;
const safeSub = @import("std").math.sub;
const safeMul = @import("std").math.mul;
const safeDivFloor = @import("std").math.divFloor;

fn int_plus(args: []*MalType) MalError!*MalType {
    if (args.len != 2) return MalError.ArgError;
    const a1 = args[0];
    const a2 = args[1];
    const x = try a1.as_int();
    const y = try a2.as_int();
    const res = try safeAdd(i64, x, y);
    return MalType.new_int(res);
}

fn int_minus(args: []*MalType) MalError!*MalType {
    if (args.len != 2) return MalError.ArgError;
    const a1 = args[0];
    const a2 = args[1];
    const x = try a1.as_int();
    const y = try a2.as_int();
    const res = try safeSub(i64, x, y);
    return MalType.new_int(res);
}

fn int_mult(args: []*MalType) MalError!*MalType {
    if (args.len != 2) return MalError.ArgError;
    const a1 = args[0];
    const a2 = args[1];
    const x = try a1.as_int();
    const y = try a2.as_int();
    const res = try safeMul(i64, x, y);
    return MalType.new_int(res);
}

fn int_div(args: []*MalType) MalError!*MalType {
    if (args.len != 2) return MalError.ArgError;
    const a1 = args[0];
    const a2 = args[1];
    const x = try a1.as_int();
    const y = try a2.as_int();
    const res = try safeDivFloor(i64, x, y);
    return MalType.new_int(res);
}

fn make_environment() !void {

    const plus_sym = try MalType.new_symbol("+", true);
    const plus_mal = try MalType.newFnCore(&int_plus);
    try repl_environment.put(Allocator, plus_sym, plus_mal);
    const minus_sym = try MalType.new_symbol("-", true);
    const minus_mal = try MalType.newFnCore(&int_minus);
    try repl_environment.put(Allocator, minus_sym, minus_mal);
    const mult_sym = try MalType.new_symbol("*", true);
    const mult_mal = try MalType.newFnCore(&int_mult);
    try repl_environment.put(Allocator, mult_sym, mult_mal);
    const div_sym = try MalType.new_symbol("/", true);
    const div_mal = try MalType.newFnCore(&int_div);
    try repl_environment.put(Allocator, div_sym, div_mal);
}

pub fn apply_function(f: MalType, args: []*MalType) MalError!*MalType {

    switch(f) {
        .FnCore => |fncoredata| {
            return fncoredata.data(args);
        },
        else => {
            return MalError.ApplyError;
        },
    }
}

pub fn main() !void {
    try make_environment();

    while(try getline("user> ")) |line| {
        defer Allocator.free(line);
        rep(line) catch |err| {
            try stdout_file.writeAll("Error: ");
            try stdout_file.writeAll(@errorName(err));
            try stdout_file.writeAll("\n");
            if(get_error_data()) |mal| {
                defer mal.decref();
                try stdout_file.writeAll("MAL error object is: ");
                try PRINT(mal.*);
            }
        };
    }
}