#!/usr/bin/env python
#coding: utf-8
#
# Usage: run `command script import -r misc/lldb_cruby.py` on LLDB
#
# Test: misc/test_lldb_cruby.rb
#

from __future__ import print_function
import lldb
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
        for i in range(0, members.GetSize()):
            member = members.GetTypeEnumMemberAtIndex(i)
            name = member.GetName()
            value = member.GetValueAsUnsigned()
            g[name] = value

            if name.startswith('RUBY_T_'):
                value_types.append(name)
    g['value_types'] = value_types

def string2cstr(rstring):
    """Returns the pointer to the C-string in the given String object"""
    if rstring.TypeIsPointerType():
        rstring = rstring.Dereference()
    flags = rstring.GetValueForExpressionPath(".basic->flags").unsigned
    if flags & RUBY_T_MASK != RUBY_T_STRING:
        raise TypeError("not a string")
    if flags & RUBY_FL_USER1:
        cptr = int(rstring.GetValueForExpressionPath(".as.heap.ptr").value, 0)
        clen = int(rstring.GetValueForExpressionPath(".as.heap.len").value, 0)
    else:
        cptr = int(rstring.GetValueForExpressionPath(".as.ary").location, 0)
        clen = (flags & RSTRING_EMBED_LEN_MASK) >> RSTRING_EMBED_LEN_SHIFT
    return cptr, clen

def output_string(debugger, result, rstring):
    cptr, clen = string2cstr(rstring)
    expr = "print *(const char (*)[%d])%0#x" % (clen, cptr)
    append_command_output(debugger, expr, result)

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
        print(error, file=result)
        return
    lldb_inspect(debugger, target, result, val)

def lldb_inspect(debugger, target, result, val):
    num = val.GetValueAsSigned()
    if num == RUBY_Qfalse:
        print('false', file=result)
    elif num == RUBY_Qtrue:
        print('true', file=result)
    elif num == RUBY_Qnil:
        print('nil', file=result)
    elif num == RUBY_Qundef:
        print('undef', file=result)
    elif fixnum_p(num):
        print(num >> 1, file=result)
    elif flonum_p(num):
        append_command_output(debugger, "print rb_float_value(%0#x)" % val.GetValueAsUnsigned(), result)
    elif static_sym_p(num):
        if num < 128:
            print("T_SYMBOL: %c" % num, file=result)
        else:
            print("T_SYMBOL: (%x)" % num, file=result)
            append_command_output(debugger, "p rb_id2name(%0#x)" % (num >> 8), result)
    elif num & RUBY_IMMEDIATE_MASK:
        print('immediate(%x)' % num, file=result)
    else:
        tRBasic = target.FindFirstType("struct RBasic").GetPointerType()
        val = val.Cast(tRBasic)
        flags = val.GetValueForExpressionPath("->flags").GetValueAsUnsigned()
        flaginfo = ""
        if (flags & RUBY_FL_PROMOTED) == RUBY_FL_PROMOTED:
            flaginfo += "[PROMOTED] "
        if (flags & RUBY_FL_FREEZE) == RUBY_FL_FREEZE:
            flaginfo += "[FROZEN] "
        flType = flags & RUBY_T_MASK
        if flType == RUBY_T_NONE:
            print('T_NONE: %s%s' % (flaginfo, val.Dereference()), file=result)
        elif flType == RUBY_T_NIL:
            print('T_NIL: %s%s' % (flaginfo, val.Dereference()), file=result)
        elif flType == RUBY_T_OBJECT:
            result.write('T_OBJECT: %s' % flaginfo)
            append_command_output(debugger, "print *(struct RObject*)%0#x" % val.GetValueAsUnsigned(), result)
        elif flType == RUBY_T_CLASS or flType == RUBY_T_MODULE or flType == RUBY_T_ICLASS:
            result.write('T_%s: %s' % ('CLASS' if flType == RUBY_T_CLASS else 'MODULE' if flType == RUBY_T_MODULE else 'ICLASS', flaginfo))
            append_command_output(debugger, "print *(struct RClass*)%0#x" % val.GetValueAsUnsigned(), result)
        elif flType == RUBY_T_STRING:
            result.write('T_STRING: %s' % flaginfo)
            tRString = target.FindFirstType("struct RString").GetPointerType()
            ptr, len = string2cstr(val.Cast(tRString))
            if len == 0:
                result.write("(empty)\n")
            else:
                append_command_output(debugger, "print *(const char (*)[%d])%0#x" % (len, ptr), result)
        elif flType == RUBY_T_SYMBOL:
            result.write('T_SYMBOL: %s' % flaginfo)
            tRSymbol = target.FindFirstType("struct RSymbol").GetPointerType()
            val = val.Cast(tRSymbol)
            append_command_output(debugger, 'print (ID)%0#x ' % val.GetValueForExpressionPath("->id").GetValueAsUnsigned(), result)
            tRString = target.FindFirstType("struct RString").GetPointerType()
            output_string(debugger, result, val.GetValueForExpressionPath("->fstr").Cast(tRString))
        elif flType == RUBY_T_ARRAY:
            tRArray = target.FindFirstType("struct RArray").GetPointerType()
            val = val.Cast(tRArray)
            if flags & RUBY_FL_USER1:
                len = ((flags & (RUBY_FL_USER3|RUBY_FL_USER4)) >> (RUBY_FL_USHIFT+3))
                ptr = val.GetValueForExpressionPath("->as.ary")
            else:
                len = val.GetValueForExpressionPath("->as.heap.len").GetValueAsSigned()
                ptr = val.GetValueForExpressionPath("->as.heap.ptr")
                #print(val.GetValueForExpressionPath("->as.heap"), file=result)
            result.write("T_ARRAY: %slen=%d" % (flaginfo, len))
            if flags & RUBY_FL_USER1:
                result.write(" (embed)")
            elif flags & RUBY_FL_USER2:
                shared = val.GetValueForExpressionPath("->as.heap.aux.shared").GetValueAsUnsigned()
                result.write(" (shared) shared=%016x" % shared)
            else:
                capa = val.GetValueForExpressionPath("->as.heap.aux.capa").GetValueAsSigned()
                result.write(" (ownership) capa=%d" % capa)
            if len == 0:
                result.write(" {(empty)}\n")
            else:
                result.write("\n")
                if ptr.GetValueAsSigned() == 0:
                    append_command_output(debugger, "expression -fx -- ((struct RArray*)%0#x)->as.ary" % val.GetValueAsUnsigned(), result)
                else:
                    append_command_output(debugger, "expression -Z %d -fx -- (const VALUE*)%0#x" % (len, ptr.GetValueAsUnsigned()), result)
        elif flType == RUBY_T_HASH:
            result.write("T_HASH: %s" % flaginfo)
            append_command_output(debugger, "p *(struct RHash *) %0#x" % val.GetValueAsUnsigned(), result)
        elif flType == RUBY_T_BIGNUM:
            tRBignum = target.FindFirstType("struct RBignum").GetPointerType()
            val = val.Cast(tRBignum)
            sign = '+' if (flags & RUBY_FL_USER1) != 0 else '-'
            if flags & RUBY_FL_USER2:
                len = ((flags & (RUBY_FL_USER3|RUBY_FL_USER4|RUBY_FL_USER5)) >> (RUBY_FL_USHIFT+3))
                print("T_BIGNUM: sign=%s len=%d (embed)" % (sign, len), file=result)
                append_command_output(debugger, "print ((struct RBignum *) %0#x)->as.ary" % val.GetValueAsUnsigned(), result)
            else:
                len = val.GetValueForExpressionPath("->as.heap.len").GetValueAsSigned()
                print("T_BIGNUM: sign=%s len=%d" % (sign, len), file=result)
                print(val.Dereference(), file=result)
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
            print("(Complex) " + real + imag + "i", file=result)
        elif flType == RUBY_T_REGEXP:
            tRRegex = target.FindFirstType("struct RRegexp").GetPointerType()
            val = val.Cast(tRRegex)
            print("(Regex) ->src {", file=result)
            lldb_inspect(debugger, target, result, val.GetValueForExpressionPath("->src"))
            print("}", file=result)
        elif flType == RUBY_T_DATA:
            tRTypedData = target.FindFirstType("struct RTypedData").GetPointerType()
            val = val.Cast(tRTypedData)
            flag = val.GetValueForExpressionPath("->typed_flag")
            if flag.GetValueAsUnsigned() == 1:
                print("T_DATA: %s" % val.GetValueForExpressionPath("->type->wrap_struct_name"), file=result)
                append_command_output(debugger, "p *(struct RTypedData *) %0#x" % val.GetValueAsUnsigned(), result)
            else:
                print("T_DATA:", file=result)
                append_command_output(debugger, "p *(struct RData *) %0#x" % val.GetValueAsUnsigned(), result)
        elif flType == RUBY_T_NODE:
            tRTypedData = target.FindFirstType("struct RNode").GetPointerType()
            nd_type = (flags & RUBY_NODE_TYPEMASK) >> RUBY_NODE_TYPESHIFT
            append_command_output(debugger, "p (node_type) %d" % nd_type, result)
            val = val.Cast(tRTypedData)
            append_command_output(debugger, "p *(struct RNode *) %0#x" % val.GetValueAsUnsigned(), result)
        elif flType == RUBY_T_MOVED:
            tRTypedData = target.FindFirstType("struct RMoved").GetPointerType()
            val = val.Cast(tRTypedData)
            append_command_output(debugger, "p *(struct RMoved *) %0#x" % val.GetValueAsUnsigned(), result)
        elif flType == RUBY_T_IMEMO:
            # I'm not sure how to get IMEMO_MASK out of lldb. It's not in globals()
            imemo_type = (flags >> RUBY_FL_USHIFT) & 0x0F # IMEMO_MASK
            print("T_IMEMO: ", file=result)
            append_command_output(debugger, "p (enum imemo_type) %d" % imemo_type, result)
            append_command_output(debugger, "p *(struct MEMO *) %0#x" % val.GetValueAsUnsigned(), result)
        elif flType == RUBY_T_ZOMBIE:
            tRZombie = target.FindFirstType("struct RZombie").GetPointerType()
            val = val.Cast(tRZombie)
            append_command_output(debugger, "p *(struct RZombie *) %0#x" % val.GetValueAsUnsigned(), result)
        else:
            print("Not-handled type %0#x" % flType, file=result)
            print(val, file=result)

def count_objects(debugger, command, ctx, result, internal_dict):
    objspace = ctx.frame.EvaluateExpression("ruby_current_vm->objspace")
    num_pages = objspace.GetValueForExpressionPath(".heap_pages.allocated_pages").unsigned

    counts = {}
    total = 0
    for t in range(0x00, RUBY_T_MASK+1):
        counts[t] = 0

    for i in range(0, num_pages):
        print("\rcounting... %d/%d" % (i, num_pages), end="")
        page = objspace.GetValueForExpressionPath('.heap_pages.sorted[%d]' % i)
        p = page.GetChildMemberWithName('start')
        num_slots = page.GetChildMemberWithName('total_slots').unsigned
        for j in range(0, num_slots):
            obj = p.GetValueForExpressionPath('[%d]' % j)
            flags = obj.GetValueForExpressionPath('.as.basic.flags').unsigned
            obj_type = flags & RUBY_T_MASK
            counts[obj_type] += 1
        total += num_slots

    print("\rTOTAL: %d, FREE: %d" % (total, counts[0x00]))
    for sym in value_types:
        print("%s: %d" % (sym, counts[globals()[sym]]))

def stack_dump_raw(debugger, command, ctx, result, internal_dict):
    ctx.frame.EvaluateExpression("rb_vmdebug_stack_dump_raw_current()")

def dump_node(debugger, command, ctx, result, internal_dict):
    args = shlex.split(command)
    if not args:
        return
    node = args[0]

    dump = ctx.frame.EvaluateExpression("(struct RString*)rb_parser_dump_tree((NODE*)(%s), 0)" % node)
    output_string(ctx, result, dump)

def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand("command script add -f lldb_cruby.lldb_rp rp")
    debugger.HandleCommand("command script add -f lldb_cruby.count_objects rb_count_objects")
    debugger.HandleCommand("command script add -f lldb_cruby.stack_dump_raw SDR")
    debugger.HandleCommand("command script add -f lldb_cruby.dump_node dump_node")
    lldb_init(debugger)
    print("lldb scripts for ruby has been installed.")
