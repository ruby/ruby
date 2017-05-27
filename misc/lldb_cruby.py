#!/usr/bin/env python
#coding: utf-8
#
# Usage: run `command script import -r misc/lldb_cruby.py` on LLDB
#

import lldb
import commands
import os
import shlex

RUBY_T_NONE   = 0x00

RUBY_T_OBJECT = 0x01
RUBY_T_CLASS  = 0x02
RUBY_T_MODULE = 0x03
RUBY_T_FLOAT  = 0x04
RUBY_T_STRING = 0x05
RUBY_T_REGEXP = 0x06
RUBY_T_ARRAY  = 0x07
RUBY_T_HASH   = 0x08
RUBY_T_STRUCT = 0x09
RUBY_T_BIGNUM = 0x0a
RUBY_T_FILE   = 0x0b
RUBY_T_DATA   = 0x0c
RUBY_T_MATCH  = 0x0d
RUBY_T_COMPLEX  = 0x0e
RUBY_T_RATIONAL = 0x0f

RUBY_T_NIL    = 0x11
RUBY_T_TRUE   = 0x12
RUBY_T_FALSE  = 0x13
RUBY_T_SYMBOL = 0x14
RUBY_T_FIXNUM = 0x15
RUBY_T_UNDEF  = 0x16

RUBY_T_IMEMO  = 0x1a
RUBY_T_NODE   = 0x1b
RUBY_T_ICLASS = 0x1c
RUBY_T_ZOMBIE = 0x1d

RUBY_T_MASK   = 0x1f


RUBY_FL_WB_PROTECTED = (1<<5)
RUBY_FL_PROMOTED0 = (1<<5)
RUBY_FL_PROMOTED1 = (1<<6)
RUBY_FL_PROMOTED  = RUBY_FL_PROMOTED0|RUBY_FL_PROMOTED1
RUBY_FL_FINALIZE  = (1<<7)
RUBY_FL_TAINT     = (1<<8)
RUBY_FL_UNTRUSTED = RUBY_FL_TAINT
RUBY_FL_EXIVAR    = (1<<10)
RUBY_FL_FREEZE    = (1<<11)

RUBY_FL_USHIFT    = 12

RUBY_FL_USER0 = (1<<(RUBY_FL_USHIFT+0))
RUBY_FL_USER1 = (1<<(RUBY_FL_USHIFT+1))
RUBY_FL_USER2 = (1<<(RUBY_FL_USHIFT+2))
RUBY_FL_USER3 = (1<<(RUBY_FL_USHIFT+3))
RUBY_FL_USER4 = (1<<(RUBY_FL_USHIFT+4))
RUBY_FL_USER5 = (1<<(RUBY_FL_USHIFT+5))
RUBY_FL_USER6 = (1<<(RUBY_FL_USHIFT+6))
RUBY_FL_USER7 = (1<<(RUBY_FL_USHIFT+7))
RUBY_FL_USER8 = (1<<(RUBY_FL_USHIFT+8))
RUBY_FL_USER9 = (1<<(RUBY_FL_USHIFT+9))
RUBY_FL_USER10 = (1<<(RUBY_FL_USHIFT+10))
RUBY_FL_USER11 = (1<<(RUBY_FL_USHIFT+11))
RUBY_FL_USER12 = (1<<(RUBY_FL_USHIFT+12))
RUBY_FL_USER13 = (1<<(RUBY_FL_USHIFT+13))
RUBY_FL_USER14 = (1<<(RUBY_FL_USHIFT+14))
RUBY_FL_USER15 = (1<<(RUBY_FL_USHIFT+15))
RUBY_FL_USER16 = (1<<(RUBY_FL_USHIFT+16))
RUBY_FL_USER17 = (1<<(RUBY_FL_USHIFT+17))
RUBY_FL_USER18 = (1<<(RUBY_FL_USHIFT+18))
RUBY_FL_USER19 = (1<<(RUBY_FL_USHIFT+19))

RSTRING_NOEMBED = RUBY_FL_USER1

def lldb_rp(debugger, command, result, internal_dict):
    target = debugger.GetSelectedTarget()
    process = target.GetProcess()
    thread = process.GetSelectedThread()
    frame = thread.GetSelectedFrame()
    val = frame.EvaluateExpression(command)
    num = val.GetValueAsSigned()
    if num == 0:
        print('false')
    elif num == 0x14:
        print('nil')
    elif num == 8:
        print('nil')
    elif num == 0x34:
        print('Qundef')
    elif num & 1 != 0:
        print(num >> 1)
    else:
        tRBasic = target.FindFirstType("struct RBasic").GetPointerType()
        val = val.Cast(tRBasic)
        flags = val.GetValueForExpressionPath("->flags").GetValueAsUnsigned()
        flType = flags & RUBY_T_MASK
        if flType == RUBY_T_STRING:
            tRString = target.FindFirstType("struct RString").GetPointerType()
            val = val.Cast(tRString)
            if flags & RSTRING_NOEMBED:
                print(val.GetValueForExpressionPath("->as.heap"))
            else:
                print(val.GetValueForExpressionPath("->as.ary"))
        elif flType == RUBY_T_ARRAY:
            tRArray = target.FindFirstType("struct RArray").GetPointerType()
            val = val.Cast(tRArray)
            if flags & RUBY_FL_USER1:
                len = ((flags & (RUBY_FL_USER3|RUBY_FL_USER4)) >> (RUBY_FL_USHIFT+3))
                print("T_ARRAY: len=%d (embed)" % len)
                if len == 0:
                    print "{(empty)}"
                else:
                    print(val.GetValueForExpressionPath("->as.ary"))
            else:
                len = val.GetValueForExpressionPath("->as.heap.len").GetValueAsSigned()
                print("T_ARRAY: len=%d " % len)
                #print(val.GetValueForExpressionPath("->as.heap"))
                if flags & RUBY_FL_USER2:
                    shared = val.GetValueForExpressionPath("->as.heap.aux.shared").GetValueAsUnsigned()
                    print "(shared) shared=%016x " % shared
                else:
                    capa = val.GetValueForExpressionPath("->as.heap.aux.capa").GetValueAsSigned()
                    print "(ownership) capa=%d " % capa
                if len == 0:
                    print "{(empty)}"
                else:
                   debugger.HandleCommand("expression -Z %d -fx -- (const VALUE*)((struct RArray*)%d)->as.heap.ptr" % (len, val.GetValueAsUnsigned()))
            debugger.HandleCommand("p (struct RArray *) %0#x" % val.GetValueAsUnsigned())


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand("command script add -f lldb_cruby.lldb_rp rp")
    print "lldb scripts for ruby has been installed."
