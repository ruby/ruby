#coding: utf-8
#
# Usage: run `command script import -r misc/lldb_cruby.py` on LLDB
#
# Test: misc/test_lldb_cruby.rb
#

from __future__ import print_function
import lldb
import os
import inspect
import sys
import shlex
import platform
import glob
import math

from lldb_rb.constants import *

# BEGIN FUNCTION STYLE DECLS
# This will be refactored to use class style decls in the misc/commands dir
class BackTrace:
    VM_FRAME_MAGIC_METHOD = 0x11110001
    VM_FRAME_MAGIC_BLOCK = 0x22220001
    VM_FRAME_MAGIC_CLASS = 0x33330001
    VM_FRAME_MAGIC_TOP = 0x44440001
    VM_FRAME_MAGIC_CFUNC = 0x55550001
    VM_FRAME_MAGIC_IFUNC = 0x66660001
    VM_FRAME_MAGIC_EVAL = 0x77770001
    VM_FRAME_MAGIC_RESCUE = 0x78880001
    VM_FRAME_MAGIC_DUMMY = 0x79990001

    VM_FRAME_MAGIC_MASK = 0x7fff0001

    VM_FRAME_MAGIC_NAME = {
            VM_FRAME_MAGIC_TOP: "TOP",
            VM_FRAME_MAGIC_METHOD: "METHOD",
            VM_FRAME_MAGIC_CLASS: "CLASS",
            VM_FRAME_MAGIC_BLOCK: "BLOCK",
            VM_FRAME_MAGIC_CFUNC: "CFUNC",
            VM_FRAME_MAGIC_IFUNC: "IFUNC",
            VM_FRAME_MAGIC_EVAL: "EVAL",
            VM_FRAME_MAGIC_RESCUE: "RESCUE",
            0: "-----"
    }

    def __init__(self, debugger, command, result, internal_dict):
        self.debugger = debugger
        self.command = command
        self.result = result

        self.target = debugger.GetSelectedTarget()
        self.process = self.target.GetProcess()
        self.thread = self.process.GetSelectedThread()
        self.frame = self.thread.GetSelectedFrame()
        self.tRString = self.target.FindFirstType("struct RString").GetPointerType()
        self.tRArray = self.target.FindFirstType("struct RArray").GetPointerType()

        rb_cft_len = len("rb_control_frame_t")
        method_type_length = sorted(map(len, self.VM_FRAME_MAGIC_NAME.values()), reverse=True)[0]
        # cfp address, method type, function name
        self.fmt = "%%-%ds %%-%ds %%s" % (rb_cft_len, method_type_length)

    def vm_frame_magic(self, cfp):
        ep = cfp.GetValueForExpressionPath("->ep")
        frame_type = ep.GetChildAtIndex(0).GetValueAsUnsigned() & self.VM_FRAME_MAGIC_MASK
        return self.VM_FRAME_MAGIC_NAME.get(frame_type, "(none)")

    def rb_iseq_path_str(self, iseq):
        tRBasic = self.target.FindFirstType("::RBasic").GetPointerType()

        pathobj = iseq.GetValueForExpressionPath("->body->location.pathobj")
        pathobj = pathobj.Cast(tRBasic)
        flags = pathobj.GetValueForExpressionPath("->flags").GetValueAsUnsigned()
        flType = flags & RUBY_T_MASK

        if flType == RUBY_T_ARRAY:
            pathobj = pathobj.Cast(self.tRArray)

            if flags & RUBY_FL_USER1:
                len = ((flags & (RUBY_FL_USER3|RUBY_FL_USER4|RUBY_FL_USER5|RUBY_FL_USER6|RUBY_FL_USER7|RUBY_FL_USER8|RUBY_FL_USER9)) >> (RUBY_FL_USHIFT+3))
                ptr = pathobj.GetValueForExpressionPath("->as.ary")
            else:
                len = pathobj.GetValueForExpressionPath("->as.heap.len").GetValueAsSigned()
                ptr = pathobj.GetValueForExpressionPath("->as.heap.ptr")

            pathobj = ptr.GetChildAtIndex(0)

        pathobj = pathobj.Cast(self.tRString)
        ptr, len = string2cstr(pathobj)
        err = lldb.SBError()
        path = self.target.process.ReadMemory(ptr, len, err)
        if err.Success():
            return path.decode("utf-8")
        else:
            return "unknown"

    def dump_iseq_frame(self, cfp, iseq):
        m = self.vm_frame_magic(cfp)

        if iseq.GetValueAsUnsigned():
            iseq_label = iseq.GetValueForExpressionPath("->body->location.label")
            path = self.rb_iseq_path_str(iseq)
            ptr, len = string2cstr(iseq_label.Cast(self.tRString))

            err = lldb.SBError()
            iseq_name = self.target.process.ReadMemory(ptr, len, err)
            if err.Success():
                iseq_name = iseq_name.decode("utf-8")
            else:
                iseq_name = "error!!"

        else:
            print("No iseq", file=self.result)

        print(self.fmt % (("%0#12x" % cfp.GetAddress().GetLoadAddress(self.target)), m, "%s %s" % (path, iseq_name)), file=self.result)

    def dump_cfunc_frame(self, cfp):
        print(self.fmt % ("%0#12x" % (cfp.GetAddress().GetLoadAddress(self.target)), "CFUNC", ""), file=self.result)

    def print_bt(self, ec):
        tRbExecutionContext_t = self.target.FindFirstType("rb_execution_context_t")
        ec = ec.Cast(tRbExecutionContext_t.GetPointerType())
        vm_stack = ec.GetValueForExpressionPath("->vm_stack")
        vm_stack_size = ec.GetValueForExpressionPath("->vm_stack_size")

        last_cfp_frame = ec.GetValueForExpressionPath("->cfp")
        cfp_type_p = last_cfp_frame.GetType()

        stack_top = vm_stack.GetValueAsUnsigned() + (
                vm_stack_size.GetValueAsUnsigned() * vm_stack.GetType().GetByteSize())

        cfp_frame_size = cfp_type_p.GetPointeeType().GetByteSize()

        start_cfp = stack_top
        # Skip dummy frames
        start_cfp -= cfp_frame_size
        start_cfp -= cfp_frame_size

        last_cfp = last_cfp_frame.GetValueAsUnsigned()

        size = ((start_cfp - last_cfp) / cfp_frame_size) + 1

        print(self.fmt % ("rb_control_frame_t", "TYPE", ""), file=self.result)

        curr_addr = start_cfp

        while curr_addr >= last_cfp:
            cfp = self.target.CreateValueFromAddress("cfp", lldb.SBAddress(curr_addr, self.target), cfp_type_p.GetPointeeType())
            ep = cfp.GetValueForExpressionPath("->ep")
            iseq = cfp.GetValueForExpressionPath("->iseq")

            frame_type = ep.GetChildAtIndex(0).GetValueAsUnsigned() & self.VM_FRAME_MAGIC_MASK

            if iseq.GetValueAsUnsigned():
                pc = cfp.GetValueForExpressionPath("->pc")
                if pc.GetValueAsUnsigned():
                    self.dump_iseq_frame(cfp, iseq)
            else:
                if frame_type == self.VM_FRAME_MAGIC_CFUNC:
                    self.dump_cfunc_frame(cfp)

            curr_addr -= cfp_frame_size

def lldb_init(debugger):
    target = debugger.GetSelectedTarget()
    global SIZEOF_VALUE
    SIZEOF_VALUE = target.FindFirstType("VALUE").GetByteSize()

    value_types = []
    g = globals()

    imemo_types = target.FindFirstType('enum imemo_type')
    enum_members = imemo_types.GetEnumMembers()

    for i in range(enum_members.GetSize()):
        member = enum_members.GetTypeEnumMemberAtIndex(i)
        g[member.GetName()] = member.GetValueAsUnsigned()

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
    clen = int(rstring.GetValueForExpressionPath(".len").value, 0)
    if flags & RUBY_FL_USER1:
        cptr = int(rstring.GetValueForExpressionPath(".as.heap.ptr").value, 0)
    else:
        cptr = int(rstring.GetValueForExpressionPath(".as.embed.ary").location, 0)
    return cptr, clen

def output_string(debugger, result, rstring):
    cptr, clen = string2cstr(rstring)
    append_expression(debugger, "*(const char (*)[%d])%0#x" % (clen, cptr), result)

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

def append_expression(debugger, expression, result):
    append_command_output(debugger, "expression " + expression, result)

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
        append_expression(debugger, "rb_float_value(%0#x)" % val.GetValueAsUnsigned(), result)
    elif static_sym_p(num):
        if num < 128:
            print("T_SYMBOL: %c" % num, file=result)
        else:
            print("T_SYMBOL: (%x)" % num, file=result)
            append_expression(debugger, "rb_id2name(%0#x)" % (num >> 8), result)
    elif num & RUBY_IMMEDIATE_MASK:
        print('immediate(%x)' % num, file=result)
    else:
        tRBasic = target.FindFirstType("::RBasic").GetPointerType()

        val = val.Cast(tRBasic)
        flags = val.GetValueForExpressionPath("->flags").GetValueAsUnsigned()
        flaginfo = ""

        page = get_page(lldb, target, val)
        page_type = target.FindFirstType("struct heap_page").GetPointerType()
        page.Cast(page_type)

        dump_bits(target, result, page, val.GetValueAsUnsigned())

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
            append_expression(debugger, "*(struct RObject*)%0#x" % val.GetValueAsUnsigned(), result)
        elif flType == RUBY_T_CLASS or flType == RUBY_T_MODULE or flType == RUBY_T_ICLASS:
            result.write('T_%s: %s' % ('CLASS' if flType == RUBY_T_CLASS else 'MODULE' if flType == RUBY_T_MODULE else 'ICLASS', flaginfo))
            append_expression(debugger, "*(struct RClass*)%0#x" % val.GetValueAsUnsigned(), result)
            tRClass = target.FindFirstType("struct RClass")
            if not val.Cast(tRClass).GetChildMemberWithName("ptr").IsValid():
                append_expression(debugger, "*(struct rb_classext_struct*)%0#x" % (val.GetValueAsUnsigned() + tRClass.GetByteSize()), result)
        elif flType == RUBY_T_STRING:
            result.write('T_STRING: %s' % flaginfo)
            encidx = ((flags & RUBY_ENCODING_MASK)>>RUBY_ENCODING_SHIFT)
            encname = target.FindFirstType("enum ruby_preserved_encindex").GetEnumMembers().GetTypeEnumMemberAtIndex(encidx).GetName()
            if encname is not None:
                result.write('[%s] ' % encname[14:])
            else:
                result.write('[enc=%d] ' % encidx)
            tRString = target.FindFirstType("struct RString").GetPointerType()
            ptr, len = string2cstr(val.Cast(tRString))
            if len == 0:
                result.write("(empty)\n")
            else:
                append_expression(debugger, "*(const char (*)[%d])%0#x" % (len, ptr), result)
        elif flType == RUBY_T_SYMBOL:
            result.write('T_SYMBOL: %s' % flaginfo)
            tRSymbol = target.FindFirstType("struct RSymbol").GetPointerType()
            val = val.Cast(tRSymbol)
            append_expression(debugger, '(ID)%0#x ' % val.GetValueForExpressionPath("->id").GetValueAsUnsigned(), result)
            tRString = target.FindFirstType("struct RString").GetPointerType()
            output_string(debugger, result, val.GetValueForExpressionPath("->fstr").Cast(tRString))
        elif flType == RUBY_T_ARRAY:
            tRArray = target.FindFirstType("struct RArray").GetPointerType()
            val = val.Cast(tRArray)
            if flags & RUBY_FL_USER1:
                len = ((flags & (RUBY_FL_USER3|RUBY_FL_USER4|RUBY_FL_USER5|RUBY_FL_USER6|RUBY_FL_USER7|RUBY_FL_USER8|RUBY_FL_USER9)) >> (RUBY_FL_USHIFT+3))
                ptr = val.GetValueForExpressionPath("->as.ary")
            else:
                len = val.GetValueForExpressionPath("->as.heap.len").GetValueAsSigned()
                ptr = val.GetValueForExpressionPath("->as.heap.ptr")
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
                    append_expression(debugger, "-fx -- ((struct RArray*)%0#x)->as.ary" % val.GetValueAsUnsigned(), result)
                else:
                    append_expression(debugger, "-Z %d -fx -- (const VALUE*)%0#x" % (len, ptr.GetValueAsUnsigned()), result)
        elif flType == RUBY_T_HASH:
            result.write("T_HASH: %s" % flaginfo)
            append_expression(debugger, "*(struct RHash *) %0#x" % val.GetValueAsUnsigned(), result)
        elif flType == RUBY_T_BIGNUM:
            tRBignum = target.FindFirstType("struct RBignum").GetPointerType()
            val = val.Cast(tRBignum)
            sign = '+' if (flags & RUBY_FL_USER1) != 0 else '-'
            if flags & RUBY_FL_USER2:
                len = ((flags & (RUBY_FL_USER3|RUBY_FL_USER4|RUBY_FL_USER5)) >> (RUBY_FL_USHIFT+3))
                print("T_BIGNUM: sign=%s len=%d (embed)" % (sign, len), file=result)
                append_expression(debugger, "((struct RBignum *) %0#x)->as.ary" % val.GetValueAsUnsigned(), result)
            else:
                len = val.GetValueForExpressionPath("->as.heap.len").GetValueAsSigned()
                print("T_BIGNUM: sign=%s len=%d" % (sign, len), file=result)
                print(val.Dereference(), file=result)
                append_expression(debugger, "-Z %x -fx -- (const BDIGIT*)((struct RBignum*)%d)->as.heap.digits" % (len, val.GetValueAsUnsigned()), result)
                # append_expression(debugger, "((struct RBignum *) %0#x)->as.heap.digits / %d" % (val.GetValueAsUnsigned(), len), result)
        elif flType == RUBY_T_FLOAT:
            append_expression(debugger, "((struct RFloat *)%d)->float_value" % val.GetValueAsUnsigned(), result)
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
                append_expression(debugger, "*(struct RTypedData *) %0#x" % val.GetValueAsUnsigned(), result)
            else:
                print("T_DATA:", file=result)
                append_expression(debugger, "*(struct RData *) %0#x" % val.GetValueAsUnsigned(), result)
        elif flType == RUBY_T_NODE:
            tRTypedData = target.FindFirstType("struct RNode").GetPointerType()
            nd_type = (flags & RUBY_NODE_TYPEMASK) >> RUBY_NODE_TYPESHIFT
            append_expression(debugger, "(node_type) %d" % nd_type, result)
            val = val.Cast(tRTypedData)
            append_expression(debugger, "*(struct RNode *) %0#x" % val.GetValueAsUnsigned(), result)
        elif flType == RUBY_T_MOVED:
            tRTypedData = target.FindFirstType("struct RMoved").GetPointerType()
            val = val.Cast(tRTypedData)
            append_expression(debugger, "*(struct RMoved *) %0#x" % val.GetValueAsUnsigned(), result)
        elif flType == RUBY_T_MATCH:
            tRTypedData = target.FindFirstType("struct RMatch").GetPointerType()
            val = val.Cast(tRTypedData)
            append_expression(debugger, "*(struct RMatch *) %0#x" % val.GetValueAsUnsigned(), result)
        elif flType == RUBY_T_IMEMO:
            # I'm not sure how to get IMEMO_MASK out of lldb. It's not in globals()
            imemo_type = (flags >> RUBY_FL_USHIFT) & 0x0F # IMEMO_MASK

            print("T_IMEMO: ", file=result)
            append_expression(debugger, "(enum imemo_type) %d" % imemo_type, result)
            append_expression(debugger, "*(struct MEMO *) %0#x" % val.GetValueAsUnsigned(), result)
        elif flType == RUBY_T_STRUCT:
            tRTypedData = target.FindFirstType("struct RStruct").GetPointerType()
            val = val.Cast(tRTypedData)
            append_expression(debugger, "*(struct RStruct *) %0#x" % val.GetValueAsUnsigned(), result)
        elif flType == RUBY_T_ZOMBIE:
            tRZombie = target.FindFirstType("struct RZombie").GetPointerType()
            val = val.Cast(tRZombie)
            append_expression(debugger, "*(struct RZombie *) %0#x" % val.GetValueAsUnsigned(), result)
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

def check_bits(page, bitmap_name, bitmap_index, bitmap_bit, v):
    bits = page.GetChildMemberWithName(bitmap_name)
    plane = bits.GetChildAtIndex(bitmap_index).GetValueAsUnsigned()
    if (plane & bitmap_bit) != 0:
        return v
    else:
        return ' '

def heap_page_body(debugger, command, ctx, result, internal_dict):
    target = debugger.GetSelectedTarget()
    process = target.GetProcess()
    thread = process.GetSelectedThread()
    frame = thread.GetSelectedFrame()

    val = frame.EvaluateExpression(command)
    page = get_page_body(lldb, target, val)
    print("Page body address: ", page.GetAddress(), file=result)
    print(page, file=result)

def get_page_body(lldb, target, val):
    tHeapPageBody = target.FindFirstType("struct heap_page_body")
    addr = val.GetValueAsUnsigned()
    page_addr = addr & ~(HEAP_PAGE_ALIGN_MASK)
    address = lldb.SBAddress(page_addr, target)
    return target.CreateValueFromAddress("page", address, tHeapPageBody)

def get_page(lldb, target, val):
    body = get_page_body(lldb, target, val)
    return body.GetValueForExpressionPath("->header.page")

def dump_node(debugger, command, ctx, result, internal_dict):
    args = shlex.split(command)
    if not args:
        return
    node = args[0]

    dump = ctx.frame.EvaluateExpression("(struct RString*)rb_parser_dump_tree((NODE*)(%s), 0)" % node)
    output_string(ctx, result, dump)

def rb_backtrace(debugger, command, result, internal_dict):
    if not ('RUBY_Qfalse' in globals()):
        lldb_init(debugger)
    bt = BackTrace(debugger, command, result, internal_dict)
    frame = bt.frame

    if command:
        if frame.IsValid():
            val = frame.EvaluateExpression(command)
        else:
            val = target.EvaluateExpression(command)

        error = val.GetError()
        if error.Fail():
            print >> result, error
            return
    else:
        print("Need an EC for now")

    bt.print_bt(val)

def dump_bits(target, result, page, object_address, end = "\n"):
    slot_size = page.GetChildMemberWithName("heap").GetChildMemberWithName("slot_size").unsigned
    byte_size = 40 ** math.floor(math.log(slot_size, 40))
    tUintPtr = target.FindFirstType("uintptr_t") # bits_t

    num_in_page = (object_address & HEAP_PAGE_ALIGN_MASK) // byte_size;
    bits_bitlength = tUintPtr.GetByteSize() * 8
    bitmap_index = num_in_page // bits_bitlength
    bitmap_offset = num_in_page & (bits_bitlength - 1)
    bitmap_bit = 1 << bitmap_offset

    print("bits: [%s%s%s%s%s]" % (
        check_bits(page, "uncollectible_bits", bitmap_index, bitmap_bit, "L"),
        check_bits(page, "mark_bits", bitmap_index, bitmap_bit, "M"),
        check_bits(page, "pinned_bits", bitmap_index, bitmap_bit, "P"),
        check_bits(page, "marking_bits", bitmap_index, bitmap_bit, "R"),
        check_bits(page, "wb_unprotected_bits", bitmap_index, bitmap_bit, "U"),
        ), end=end, file=result)

class HeapPageIter:
    def __init__(self, page, target):
        self.page = page
        self.target = target
        self.start = page.GetChildMemberWithName('start').GetValueAsUnsigned();
        self.num_slots = page.GetChildMemberWithName('total_slots').unsigned
        self.slot_size = page.GetChildMemberWithName('heap').GetChildMemberWithName('slot_size').unsigned
        self.counter = 0
        self.tRBasic = target.FindFirstType("::RBasic")

    def is_valid(self):
        heap_page_header_size = self.target.FindFirstType("struct heap_page_header").GetByteSize()
        rvalue_size = self.slot_size
        heap_page_obj_limit = int((HEAP_PAGE_SIZE - heap_page_header_size) / self.slot_size)

        return (heap_page_obj_limit - 1) <= self.num_slots <= heap_page_obj_limit

    def __iter__(self):
        return self

    def __next__(self):
        if self.counter < self.num_slots:
            obj_addr_i = self.start + (self.counter * self.slot_size)
            obj_addr = lldb.SBAddress(obj_addr_i, self.target)
            slot_info = (self.counter, obj_addr_i, self.target.CreateValueFromAddress("object", obj_addr, self.tRBasic))
            self.counter += 1

            return slot_info
        else:
            raise StopIteration


def dump_page_internal(page, target, process, thread, frame, result, debugger, highlight=None):
    if not ('RUBY_Qfalse' in globals()):
        lldb_init(debugger)

    ruby_type_map = ruby_types(debugger)

    freelist = []
    fl_start = page.GetChildMemberWithName('freelist').GetValueAsUnsigned()
    free_slot = target.FindFirstType("struct free_slot")

    while fl_start > 0:
        freelist.append(fl_start)
        obj_addr = lldb.SBAddress(fl_start, target)
        obj = target.CreateValueFromAddress("object", obj_addr, free_slot)
        fl_start = obj.GetChildMemberWithName("next").GetValueAsUnsigned()

    page_iter = HeapPageIter(page, target)
    if page_iter.is_valid():
        for (page_index, obj_addr, obj) in page_iter:
            dump_bits(target, result, page, obj_addr, end= " ")
            flags = obj.GetChildMemberWithName('flags').GetValueAsUnsigned()
            flType = flags & RUBY_T_MASK

            flidx = '   '
            if flType == RUBY_T_NONE:
                try:
                    flidx = "%3d" % freelist.index(obj_addr)
                except ValueError:
                    flidx = ' -1'

            if flType == RUBY_T_NONE:
                klass = obj.GetChildMemberWithName('klass').GetValueAsUnsigned()
                result_str = "%s idx: [%3d] freelist_idx: {%s} Addr: %0#x (flags: %0#x, next: %0#x)" % (rb_type(flags, ruby_type_map), page_index, flidx, obj_addr, flags, klass)
            else:
                result_str = "%s idx: [%3d] freelist_idx: {%s} Addr: %0#x (flags: %0#x)" % (rb_type(flags, ruby_type_map), page_index, flidx, obj_addr, flags)

            if highlight == obj_addr:
                result_str = ' '.join([result_str, "<<<<<"])

            print(result_str, file=result)
    else:
        print("%s is not a valid heap page" % page, file=result)



def dump_page(debugger, command, result, internal_dict):
    target = debugger.GetSelectedTarget()
    process = target.GetProcess()
    thread = process.GetSelectedThread()
    frame = thread.GetSelectedFrame()

    tHeapPageP = target.FindFirstType("struct heap_page").GetPointerType()
    page = frame.EvaluateExpression(command)
    page = page.Cast(tHeapPageP)

    dump_page_internal(page, target, process, thread, frame, result, debugger)


def dump_page_rvalue(debugger, command, result, internal_dict):
    target = debugger.GetSelectedTarget()
    process = target.GetProcess()
    thread = process.GetSelectedThread()
    frame = thread.GetSelectedFrame()

    val = frame.EvaluateExpression(command)
    page = get_page(lldb, target, val)
    page_type = target.FindFirstType("struct heap_page").GetPointerType()
    page.Cast(page_type)

    dump_page_internal(page, target, process, thread, frame, result, debugger, highlight=val.GetValueAsUnsigned())



def rb_type(flags, ruby_types):
    flType = flags & RUBY_T_MASK
    return "%-10s" % (ruby_types.get(flType, ("%0#x" % flType)))

def ruby_types(debugger):
    target = debugger.GetSelectedTarget()

    types = {}
    for enum in target.FindFirstGlobalVariable('ruby_dummy_gdb_enums'):
        enum = enum.GetType()
        members = enum.GetEnumMembers()
        for i in range(0, members.GetSize()):
            member = members.GetTypeEnumMemberAtIndex(i)
            name = member.GetName()
            value = member.GetValueAsUnsigned()

            if name.startswith('RUBY_T_'):
                types[value] = name.replace('RUBY_', '')

    return types

def rb_ary_entry(target, ary, idx, result):
    tRArray = target.FindFirstType("struct RArray").GetPointerType()
    ary = ary.Cast(tRArray)
    flags = ary.GetValueForExpressionPath("->flags").GetValueAsUnsigned()

    if flags & RUBY_FL_USER1:
        ptr = ary.GetValueForExpressionPath("->as.ary")
    else:
        ptr = ary.GetValueForExpressionPath("->as.heap.ptr")

    ptr_addr = ptr.GetValueAsUnsigned() + (idx * ptr.GetType().GetByteSize())
    return target.CreateValueFromAddress("ary_entry[%d]" % idx, lldb.SBAddress(ptr_addr, target), ptr.GetType().GetPointeeType())

def rb_id_to_serial(id_val):
    if id_val > tLAST_OP_ID:
        return id_val >> RUBY_ID_SCOPE_SHIFT
    else:
        return id_val

def rb_id2str(debugger, command, result, internal_dict):
    if not ('RUBY_Qfalse' in globals()):
        lldb_init(debugger)

    target = debugger.GetSelectedTarget()
    process = target.GetProcess()
    thread = process.GetSelectedThread()
    frame = thread.GetSelectedFrame()
    global_symbols = target.FindFirstGlobalVariable("ruby_global_symbols")

    id_val = frame.EvaluateExpression(command).GetValueAsUnsigned()
    num = rb_id_to_serial(id_val)

    last_id = global_symbols.GetChildMemberWithName("last_id").GetValueAsUnsigned()
    ID_ENTRY_SIZE = 2
    ID_ENTRY_UNIT = int(target.FindFirstGlobalVariable("ID_ENTRY_UNIT").GetValue())

    ids = global_symbols.GetChildMemberWithName("ids")

    if (num <= last_id):
        idx = num // ID_ENTRY_UNIT
        ary = rb_ary_entry(target, ids, idx, result)
        pos = (num % ID_ENTRY_UNIT) * ID_ENTRY_SIZE
        id_str = rb_ary_entry(target, ary, pos, result)
        lldb_inspect(debugger, target, result, id_str)
# END FUNCTION STYLE DECLS


load_dir, _ = os.path.split(os.path.realpath(__file__))

for fname in glob.glob(f"{load_dir}/lldb_rb/commands/*_command.py"):
    _, basename = os.path.split(fname)
    mname, _ = os.path.splitext(basename)

    exec(f"import lldb_rb.commands.{mname}")

def __lldb_init_module(debugger, internal_dict):
    # Register all classes that subclass RbBaseCommand

    for memname, mem in inspect.getmembers(sys.modules["lldb_rb.rb_base_command"]):
        if memname == "RbBaseCommand":
            for sclass in mem.__subclasses__():
                sclass.register_lldb_command(debugger, f"{__name__}.{sclass.__module__}")


    ## FUNCTION INITS - These should be removed when converted to class commands
    debugger.HandleCommand("command script add -f lldb_cruby.lldb_rp old_rp")
    debugger.HandleCommand("command script add -f lldb_cruby.count_objects rb_count_objects")
    debugger.HandleCommand("command script add -f lldb_cruby.stack_dump_raw SDR")
    debugger.HandleCommand("command script add -f lldb_cruby.dump_node dump_node")
    debugger.HandleCommand("command script add -f lldb_cruby.heap_page_body heap_page_body")
    debugger.HandleCommand("command script add -f lldb_cruby.rb_backtrace rbbt")
    debugger.HandleCommand("command script add -f lldb_cruby.dump_page dump_page")
    debugger.HandleCommand("command script add -f lldb_cruby.dump_page_rvalue dump_page_rvalue")
    debugger.HandleCommand("command script add -f lldb_cruby.rb_id2str old_rb_id2str")

    lldb_rb.rb_base_command.RbBaseCommand.lldb_init(debugger)

    print("lldb scripts for ruby has been installed.")
