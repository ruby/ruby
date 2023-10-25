#!/usr/bin/env python
#coding: utf-8
#
# Usage: run `command script import -r misc/lldb_yjit.py` on LLDB
#

from __future__ import print_function
import lldb
import os
import shlex

def list_comments(debugger, command, result, internal_dict):
    target = debugger.GetSelectedTarget()
    process = target.GetProcess()
    thread = process.GetSelectedThread()
    frame = thread.GetSelectedFrame()

    # Get the different types we need
    rb_darray_meta_t = target.FindFirstType("rb_darray_meta_t")
    codeblock_t = target.FindFirstType("codeblock_t")
    yjit_comment = target.FindFirstType("yjit_comment")

    # Get the global variables we need
    comments = target.FindFirstGlobalVariable("yjit_code_comments")
    cb = target.FindFirstGlobalVariable("cb").Cast(codeblock_t.GetPointerType())

    # Get the address of the memory block we're using
    mem_addr = cb.GetChildMemberWithName("mem_block").GetValueAsUnsigned()

    # Find the size of the darray comment list
    meta = comments.Cast(rb_darray_meta_t.GetPointerType())
    size = meta.GetChildMemberWithName("size").GetValueAsUnsigned()

    # Get the address of the block following the metadata header
    t_offset = comments.GetValueAsUnsigned() + rb_darray_meta_t.GetByteSize()

    # Loop through each comment and print
    for t in range(0, size):
        addr = lldb.SBAddress(t_offset + (t * yjit_comment.GetByteSize()), target)
        comment = target.CreateValueFromAddress("yjit_comment", addr, yjit_comment)
        string = comment.GetChildMemberWithName("comment")
        comment_offset = mem_addr + comment.GetChildMemberWithName("offset").GetValueAsUnsigned()
        print("%0#x %s" % (comment_offset, string.GetSummary()), file = result)


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand("command script add -f lldb_yjit.list_comments lc")
