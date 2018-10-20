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

def static_sym_p(x):
    return (x&~(~0<<RUBY_SPECIAL_SHIFT)) == RUBY_SYMBOL_FLAG

def append_command_output(debugger, command, result):
    output1 = result.GetOutput()
    debugger.GetCommandInterpreter().HandleCommand(command, result)
    output2 = result.GetOutput()
    result.Clear()
    result.write(output1)
    result.write(output2)

def lldb_rp(debugger, command, result, internal_dict):
    if not ('RUBY_Qfalse' in globals()):
        lldb_init(debugger)

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
    lldb_inspect(debugger, target, result, val)

def lldb_inspect(debugger, target, result, val):
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
        append_command_output(debugger, "print rb_float_value(%0#x)" % val.GetValueAsUnsigned(), result)
    elif static_sym_p(num):
        if num < 128:
            print >> result, "T_SYMBOL: %c" % num
        else:
            print >> result, "T_SYMBOL: (%x)" % num
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
        elif flType == RUBY_T_CLASS or flType == RUBY_T_MODULE or flType == RUBY_T_ICLASS:
            tRClass = target.FindFirstType("struct RClass").GetPointerType()
            val = val.Cast(tRClass)
            print >> result, 'T_%s: %s' % ('CLASS' if flType == RUBY_T_CLASS else 'MODULE' if flType == RUBY_T_MODULE else 'ICLASS', val.Dereference())
        elif flType == RUBY_T_STRING:
            tRString = target.FindFirstType("struct RString").GetPointerType()
            val = val.Cast(tRString)
            if flags & RSTRING_NOEMBED:
                print >> result, val.GetValueForExpressionPath("->as.heap")
            else:
                print >> result, val.GetValueForExpressionPath("->as.ary")
        elif flType == RUBY_T_SYMBOL:
            tRSymbol = target.FindFirstType("struct RSymbol").GetPointerType()
            print >> result, val.Cast(tRSymbol).Dereference()
        elif flType == RUBY_T_ARRAY:
            tRArray = target.FindFirstType("struct RArray").GetPointerType()
            val = val.Cast(tRArray)
            if flags & RUBY_FL_USER1:
                len = ((flags & (RUBY_FL_USER3|RUBY_FL_USER4)) >> (RUBY_FL_USHIFT+3))
                ptr = val.GetValueForExpressionPath("->as.ary")
            else:
                len = val.GetValueForExpressionPath("->as.heap.len").GetValueAsSigned()
                ptr = val.GetValueForExpressionPath("->as.heap.ptr")
                #print >> result, val.GetValueForExpressionPath("->as.heap")
            result.write("T_ARRAY: len=%d" % len)
            if flags & RUBY_FL_USER1:
                result.write(" (embed)")
            elif flags & RUBY_FL_USER2:
                shared = val.GetValueForExpressionPath("->as.heap.aux.shared").GetValueAsUnsigned()
                result.write(" (shared) shared=%016x")
            else:
                capa = val.GetValueForExpressionPath("->as.heap.aux.capa").GetValueAsSigned()
                result.write(" (ownership) capa=%d" % capa)
            if len == 0:
                result.write(" {(empty)}")
            else:
                result.write("\n")
                append_command_output(debugger, "expression -Z %d -fx -- (const VALUE*)%0#x" % (len, ptr.GetValueAsUnsigned()), result)
        elif flType == RUBY_T_HASH:
            append_command_output(debugger, "p *(struct RHash *) %0#x" % val.GetValueAsUnsigned(), result)
        elif flType == RUBY_T_BIGNUM:
            tRBignum = target.FindFirstType("struct RBignum").GetPointerType()
            val = val.Cast(tRBignum)
            if flags & RUBY_FL_USER2:
                len = ((flags & (RUBY_FL_USER3|RUBY_FL_USER4|RUBY_FL_USER5)) >> (RUBY_FL_USHIFT+3))
                print >> result, "T_BIGNUM: len=%d (embed)" % len
                append_command_output(debugger, "print ((struct RBignum *) %0#x)->as.ary" % val.GetValueAsUnsigned(), result)
            else:
                len = val.GetValueForExpressionPath("->as.heap.len").GetValueAsSigned()
                print >> result, "T_BIGNUM: len=%d" % len
                print >> result, val.Dereference()
                append_command_output(debugger, "expression -Z %x -fx -- (const BDIGIT*)((struct RBignum*)%d)->as.heap.digits" % (len, val.GetValueAsUnsigned()), result)
                # append_command_output(debugger, "x ((struct RBignum *) %0#x)->as.heap.digits / %d" % (val.GetValueAsUnsigned(), len), result)
        elif flType == RUBY_T_FLOAT:
            tRFloat = target.FindFirstType("struct RFloat").GetPointerType()
            val = val.Cast(tRFloat)
            append_command_output(debugger, "p *(double *)%0#x" % val.GetValueForExpressionPath("->float_value").GetAddress(), result)
        elif flType == RUBY_T_RATIONAL:
            tRRational = target.FindFirstType("struct RRational").GetPointerType()
            val = val.Cast(tRRational)
            lldb_inspect(debugger, target, result, val.GetValueForExpressionPath("->num"))
            output = result.GetOutput()
            result.Clear()
            result.write("(Rational) " + output.rstrip() + " / ")
            lldb_inspect(debugger, target, result, val.GetValueForExpressionPath("->den"))
        elif flType == RUBY_T_COMPLEX:
            tRComplex = target.FindFirstType("struct RComplex").GetPointerType()
            val = val.Cast(tRComplex)
            lldb_inspect(debugger, target, result, val.GetValueForExpressionPath("->real"))
            real = result.GetOutput().rstrip()
            result.Clear()
            lldb_inspect(debugger, target, result, val.GetValueForExpressionPath("->imag"))
            imag = result.GetOutput().rstrip()
            result.Clear()
            if not imag.startswith("-"):
                imag = "+" + imag
            print >> result, "(Complex) " + real + imag + "i"
        elif flType == RUBY_T_DATA:
            tRTypedData = target.FindFirstType("struct RTypedData").GetPointerType()
            val = val.Cast(tRTypedData)
            flag = val.GetValueForExpressionPath("->typed_flag")
            if flag.GetValueAsUnsigned() == 1:
                print >> result, "T_DATA: %s" % val.GetValueForExpressionPath("->type->wrap_struct_name")
                append_command_output(debugger, "p *(struct RTypedData *) %0#x" % val.GetValueAsUnsigned(), result)
            else:
                print >> result, "T_DATA:"
                append_command_output(debugger, "p *(struct RData *) %0#x" % val.GetValueAsUnsigned(), result)
        else:
            print >> result, "Not-handled type %0#x" % flType
            print >> result, val

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
