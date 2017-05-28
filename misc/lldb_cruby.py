#!/usr/bin/env python
#coding: utf-8
#
# Usage: run `command script import -r misc/lldb_cruby.py` on LLDB
#

import lldb
import commands
import os
import shlex

def lldb_init(debugger):
    target = debugger.GetSelectedTarget()
    global SIZEOF_VALUE
    SIZEOF_VALUE = target.FindFirstType("VALUE").GetByteSize()
    g = globals()
    for enum in target.FindFirstGlobalVariable('ruby_dummy_gdb_enums'):
        enum = enum.GetType()
        members = enum.GetEnumMembers()
        for i in xrange(0, members.GetSize()):
            member = members.GetTypeEnumMemberAtIndex(i)
            name = member.GetName()
            value = member.GetValueAsUnsigned()
            g[name] = value
    global ROBJECT_EMBED_LEN_MAX, ROBJECT_EMBED
    ROBJECT_EMBED_LEN_MAX = 3
    ROBJECT_EMBED = RUBY_FL_USER1
    global RMODULE_IS_OVERLAID, RMODULE_IS_REFINEMENT, RMODULE_INCLUDED_INTO_REFINEMENT
    RMODULE_IS_OVERLAID = RUBY_FL_USER2
    RMODULE_IS_REFINEMENT = RUBY_FL_USER3
    RMODULE_INCLUDED_INTO_REFINEMENT = RUBY_FL_USER4
    global RSTRING_NOEMBED, RSTRING_EMBED_LEN_MASK, RSTRING_EMBED_LEN_SHIFT, RSTRING_EMBED_LEN_MAX, RSTRING_FSTR
    RSTRING_NOEMBED = RUBY_FL_USER1
    RSTRING_EMBED_LEN_MASK = (RUBY_FL_USER2|RUBY_FL_USER3|RUBY_FL_USER4|
			      RUBY_FL_USER5|RUBY_FL_USER6)
    RSTRING_EMBED_LEN_SHIFT = (RUBY_FL_USHIFT+2)
    RSTRING_EMBED_LEN_MAX = (SIZEOF_VALUE*3)-1
    RSTRING_FSTR = RUBY_FL_USER17

def fixnum_p(x):
    return x & RUBY_FIXNUM_FLAG != 0

def flonum_p(x):
    return (x&RUBY_FLONUM_MASK) == RUBY_FLONUM_FLAG

def lldb_rp(debugger, command, result, internal_dict):
    target = debugger.GetSelectedTarget()
    process = target.GetProcess()
    thread = process.GetSelectedThread()
    frame = thread.GetSelectedFrame()
    val = frame.EvaluateExpression(command)
    num = val.GetValueAsSigned()
    if num == RUBY_Qfalse:
        print >> result, 'false'
    elif num == RUBY_Qtrue:
        print >> result, 'true'
    elif num == RUBY_Qnil:
        print >> result, 'nil'
    elif num == RUBY_Qundef:
        print >> result, 'Qundef'
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


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand("command script add -f lldb_cruby.lldb_rp rp")
    lldb_init(debugger)
    print "lldb scripts for ruby has been installed."
