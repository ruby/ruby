#!/usr/bin/env python
#coding: utf-8
#
# Usage: run `command script import -r misc/lldb_cruby.py` on LLDB
#
# Test: misc/test_lldb_cruby.rb
#

import lldb
import commands
import os
import shlex

def lldb_init(debugger):
    target = debugger.GetSelectedTarget()
    global SIZEOF_VALUE
    SIZEOF_VALUE = target.FindFirstType("VALUE").GetByteSize()

    value_types = []
    g = globals()
    for enum in target.FindFirstGlobalVariable('ruby_dummy_gdb_enums'):
        enum = enum.GetType()
        members = enum.GetEnumMembers()
        for i in xrange(0, members.GetSize()):
            member = members.GetTypeEnumMemberAtIndex(i)
            name = member.GetName()
            value = member.GetValueAsUnsigned()
            g[name] = value

            if name.startswith('RUBY_T_'):
                value_types.append(name)
    g['value_types'] = value_types

def string2cstr(rstring):
    """Returns the pointer to the C-string in the given String object"""
    flags = rstring.GetValueForExpressionPath(".basic->flags").unsigned
    if flags & RUBY_T_MASK != RUBY_T_STRING:
        raise TypeError("not a string")
    if flags & RUBY_FL_USER1:
        cptr = int(rstring.GetValueForExpressionPath(".as.heap.ptr").value, 0)
        clen = int(rstring.GetValueForExpressionPath(".as.heap.len").value, 0)
    else:
        cptr = int(rstring.GetValueForExpressionPath(".as.ary").value, 0)
        clen = (flags & RSTRING_EMBED_LEN_MASK) >> RSTRING_EMBED_LEN_SHIFT
    return cptr, clen

def output_string(ctx, rstring):
    cptr, clen = string2cstr(rstring)
    expr = 'printf("%%.*s", (size_t)%d, (const char*)%d)' % (clen, cptr)
    ctx.frame.EvaluateExpression(expr)

def fixnum_p(x):
    return x & RUBY_FIXNUM_FLAG != 0

def flonum_p(x):
    return (x&RUBY_FLONUM_MASK) == RUBY_FLONUM_FLAG

def lldb_rp(debugger, command, result, internal_dict):
    target = debugger.GetSelectedTarget()
    process = target.GetProcess()
    thread = process.GetSelectedThread()
    frame = thread.GetSelectedFrame()
    if frame.IsValid():
        val = frame.EvaluateExpression(command)
    else:
        val = target.EvaluateExpression(command)
    error = val.GetError()
    if error.Fail():
        print >> result, error
        return
    num = val.GetValueAsSigned()
    if num == RUBY_Qfalse:
        print >> result, 'false'
    elif num == RUBY_Qtrue:
        print >> result, 'true'
    elif num == RUBY_Qnil:
        print >> result, 'nil'
    elif num == RUBY_Qundef:
        print >> result, 'undef'
    elif fixnum_p(num):
        print >> result, num >> 1
    elif flonum_p(num):
        debugger.HandleCommand("print rb_float_value(%0#x)" % val.GetValueAsUnsigned())
    elif num & RUBY_IMMEDIATE_MASK:
        print >> result, 'immediate(%x)' % num
    else:
        tRBasic = target.FindFirstType("struct RBasic").GetPointerType()
        val = val.Cast(tRBasic)
        flags = val.GetValueForExpressionPath("->flags").GetValueAsUnsigned()
        if (flags & RUBY_FL_PROMOTED) == RUBY_FL_PROMOTED:
            print >> result, "[PROMOTED] "
        flType = flags & RUBY_T_MASK
        if flType == RUBY_T_NONE:
            print >> result, 'T_NONE: %s' % val.Dereference()
        elif flType == RUBY_T_NIL:
            print >> result, 'T_NIL: %s' % val.Dereference()
        elif flType == RUBY_T_OBJECT:
            tRObject = target.FindFirstType("struct RObject").GetPointerType()
            val = val.Cast(tRObject)
            print >> result, 'T_OBJECT: %s' % val.Dereference()
        elif flType == RUBY_T_STRING:
            tRString = target.FindFirstType("struct RString").GetPointerType()
            val = val.Cast(tRString)
            if flags & RSTRING_NOEMBED:
                print >> result, val.GetValueForExpressionPath("->as.heap")
            else:
                print >> result, val.GetValueForExpressionPath("->as.ary")
        elif flType == RUBY_T_ARRAY:
            tRArray = target.FindFirstType("struct RArray").GetPointerType()
            val = val.Cast(tRArray)
            if flags & RUBY_FL_USER1:
                len = ((flags & (RUBY_FL_USER3|RUBY_FL_USER4)) >> (RUBY_FL_USHIFT+3))
                print >> result, "T_ARRAY: len=%d (embed)" % len
                if len == 0:
                    print >> result, "{(empty)}"
                else:
                    print >> result, val.GetValueForExpressionPath("->as.ary")
            else:
                len = val.GetValueForExpressionPath("->as.heap.len").GetValueAsSigned()
                print >> result, "T_ARRAY: len=%d " % len
                #print >> result, val.GetValueForExpressionPath("->as.heap")
                if flags & RUBY_FL_USER2:
                    shared = val.GetValueForExpressionPath("->as.heap.aux.shared").GetValueAsUnsigned()
                    print >> result, "(shared) shared=%016x " % shared
                else:
                    capa = val.GetValueForExpressionPath("->as.heap.aux.capa").GetValueAsSigned()
                    print >> result, "(ownership) capa=%d " % capa
                if len == 0:
                    print >> result, "{(empty)}"
                else:
                    debugger.HandleCommand("expression -Z %d -fx -- (const VALUE*)((struct RArray*)%d)->as.heap.ptr" % (len, val.GetValueAsUnsigned()))
            debugger.HandleCommand("p (struct RArray *) %0#x" % val.GetValueAsUnsigned())

def count_objects(debugger, command, ctx, result, internal_dict):
    objspace = ctx.frame.EvaluateExpression("ruby_current_vm->objspace")
    num_pages = objspace.GetValueForExpressionPath(".heap_pages.allocated_pages").unsigned

    counts = {}
    total = 0
    for t in range(0x00, RUBY_T_MASK+1):
        counts[t] = 0

    for i in range(0, num_pages):
        print "\rcounting... %d/%d" % (i, num_pages),
        page = objspace.GetValueForExpressionPath('.heap_pages.sorted[%d]' % i)
        p = page.GetChildMemberWithName('start')
        num_slots = page.GetChildMemberWithName('total_slots').unsigned
        for j in range(0, num_slots):
            obj = p.GetValueForExpressionPath('[%d]' % j)
            flags = obj.GetValueForExpressionPath('.as.basic.flags').unsigned
            obj_type = flags & RUBY_T_MASK
            counts[obj_type] += 1
        total += num_slots

    print "\rTOTAL: %d, FREE: %d" % (total, counts[0x00])
    for sym in value_types:
        print "%s: %d" % (sym, counts[globals()[sym]])

def stack_dump_raw(debugger, command, ctx, result, internal_dict):
    ctx.frame.EvaluateExpression("rb_vmdebug_stack_dump_raw_current()")

def dump_node(debugger, command, ctx, result, internal_dict):
    args = shlex.split(command)
    if not args:
        return
    node = args[0]

    dump = ctx.frame.EvaluateExpression("(struct RString*)rb_parser_dump_tree((NODE*)(%s), 0)" % node)
    output_string(ctx, dump)

def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand("command script add -f lldb_cruby.lldb_rp rp")
    debugger.HandleCommand("command script add -f lldb_cruby.count_objects rb_count_objects")
    debugger.HandleCommand("command script add -f lldb_cruby.stack_dump_raw SDR")
    debugger.HandleCommand("command script add -f lldb_cruby.dump_node dump_node")
    lldb_init(debugger)
    print "lldb scripts for ruby has been installed."
