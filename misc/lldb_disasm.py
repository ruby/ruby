#!/usr/bin/env python
#coding: utf-8
#
# Usage: run `command script import -r misc/lldb_disasm.py` on LLDB
#
#
#    (lldb) p iseq
#    (rb_iseq_t *) $147 = 0x0000000101068400
#    (lldb) rbdisasm iseq
#    0000 putspecialobject( 3 )
#    0002 putnil
#    0003 defineclass( ID: 0x560b, (rb_iseq_t *)0x1010681d0, 2 )
#    0007 pop
#    0008 putspecialobject( 3 )
#    0010 putnil
#    0011 defineclass( ID: 0x56eb, (rb_iseq_t *)0x101063b58, 2 )
#    0015 leave


import lldb
import os
import shlex

class IseqDissassembler:
    TS_VARIABLE = b'.'[0]
    TS_CALLDATA = b'C'[0]
    TS_CDHASH   = b'H'[0]
    TS_IC       = b'K'[0]
    TS_IVC      = b'A'[0]
    TS_ID       = b'I'[0]
    TS_ISE      = b'T'[0]
    TS_ISEQ     = b'S'[0]
    TS_OFFSET   = b'O'[0]
    TS_VALUE    = b'V'[0]
    TS_LINDEX   = b'L'[0]
    TS_FUNCPTR  = b'F'[0]
    TS_NUM      = b'N'[0]
    TS_BUILTIN  = b'R'[0]

    ISEQ_OPT_DISPATCH = {
            TS_BUILTIN: "(rb_builtin_function *)%0#x",
            TS_NUM: "%d",
            TS_FUNCPTR: "(rb_insn_func_t) %0#x",
            TS_LINDEX: "%d",
            TS_VALUE: "(VALUE)%0#x",
            TS_OFFSET: "%d",
            TS_ISEQ: "(rb_iseq_t *)%0#x",
            TS_ISE: "(iseq_inline_storage_entry *)%0#x",
            TS_ID: "ID: %0#x",
            TS_IVC: "(struct iseq_inline_iv_cache_entry *)%0#x",
            TS_IC: "(struct iseq_inline_cache_entry *)%0#x",
            TS_CDHASH: "CDHASH (VALUE)%0#x",
            TS_CALLDATA: "(struct rb_call_data *)%0#x",
            TS_VARIABLE: "VARIABLE %0#x",
    }

    def __init__(self, debugger, command, result, internal_dict):
        self.debugger = debugger
        self.command = command
        self.result = result
        self.internal_dict = internal_dict

        self.target = debugger.GetSelectedTarget()
        self.process = self.target.GetProcess()
        self.thread = self.process.GetSelectedThread()
        self.frame = self.thread.GetSelectedFrame()
        self.addr2insn = self.build_addr2insn(self.target)
        self.tChar = self.target.FindFirstType("char")

    def disasm(self, val):
        tRbISeq = self.target.FindFirstType("struct rb_iseq_struct").GetPointerType()
        val = val.Cast(tRbISeq)
        iseq_size = val.GetValueForExpressionPath("->body->iseq_size").GetValueAsUnsigned()
        iseqs = val.GetValueForExpressionPath("->body->iseq_encoded")
        idx = 0
        print("PC             IDX  insn_name(operands) ", file=self.result)
        while idx < iseq_size:
            m = self.iseq_extract_values(self.debugger, self.target, self.process, self.result, iseqs, idx)
            if m < 1:
                print("Error decoding", file=self.result)
                return
            else:
                idx += m

    def build_addr2insn(self, target):
        tIntPtr = target.FindFirstType("intptr_t")
        size = target.EvaluateExpression('ruby_vminsn_type::VM_INSTRUCTION_SIZE').unsigned
        sizeOfIntPtr = tIntPtr.GetByteSize()
        addr_of_table = target.FindSymbols("vm_exec_core.insns_address_table")[0].GetSymbol().GetStartAddress().GetLoadAddress(target)

        my_dict = {}

        for insn in range(size):
            addr_in_table = addr_of_table + (insn * sizeOfIntPtr)
            addr = lldb.SBAddress(addr_in_table, target)
            machine_insn = target.CreateValueFromAddress("insn", addr, tIntPtr).GetValueAsUnsigned()
            my_dict[machine_insn] = insn

        return my_dict

    def rb_vm_insn_addr2insn2(self, target, result, wanted_addr):
        return self.addr2insn.get(wanted_addr)

    def iseq_extract_values(self, debugger, target, process, result, iseqs, n):
        tValueP      = target.FindFirstType("VALUE")
        sizeofValueP = tValueP.GetByteSize()
        pc = iseqs.unsigned + (n * sizeofValueP)
        insn = target.CreateValueFromAddress("i", lldb.SBAddress(pc, target), tValueP)
        addr         = insn.GetValueAsUnsigned()
        orig_insn    = self.rb_vm_insn_addr2insn2(target, result, addr)

        name     = self.insn_name(target, process, result, orig_insn)
        length   = self.insn_len(target, orig_insn)
        op_str = self.insn_op_types(target, process, result, orig_insn)
        op_types = bytes(op_str, 'utf-8')

        if length != (len(op_types) + 1):
            print("error decoding iseqs", file=result)
            return -1

        print("%0#14x %04d %s" % (pc, n, name), file=result, end="")

        if length == 1:
            print("", file=result)
            return length

        print("(", end="", file=result)
        for idx, op_type in enumerate(op_types):
            if idx == 0:
                print(" ", end="", file=result)
            else:
                print(", ", end="", file=result)

            opAddr = lldb.SBAddress(iseqs.unsigned + ((n + idx + 1) * sizeofValueP), target)
            opValue = target.CreateValueFromAddress("op", opAddr, tValueP)
            op = opValue.GetValueAsUnsigned()
            print(self.ISEQ_OPT_DISPATCH.get(op_type) % op, end="", file=result)

        print(" )", file=result)
        return length

    def insn_len(self, target, offset):
        size_of_char = self.tChar.GetByteSize()

        symbol = target.FindSymbols("insn_len.t")[0].GetSymbol()
        section = symbol.GetStartAddress().GetSection()
        addr_of_table = symbol.GetStartAddress().GetOffset()

        error = lldb.SBError()
        length = section.GetSectionData().GetUnsignedInt8(error, addr_of_table + (offset * size_of_char))

        if error.Success():
            return length
        else:
            print("error getting length: ", error)

    def insn_op_types(self, target, process, result, insn):
        tUShort = target.FindFirstType("unsigned short")

        size_of_short = tUShort.GetByteSize()
        size_of_char =  self.tChar.GetByteSize()

        symbol = target.FindSymbols("insn_op_types.y")[0].GetSymbol()
        section = symbol.GetStartAddress().GetSection()
        addr_of_table = symbol.GetStartAddress().GetOffset()

        addr_in_table = addr_of_table + (insn * size_of_short)

        error = lldb.SBError()
        offset = section.GetSectionData().GetUnsignedInt16(error, addr_in_table)

        if not error.Success():
            print("error getting op type offset: ", error)

        symbol = target.FindSymbols("insn_op_types.x")[0].GetSymbol()
        section = symbol.GetStartAddress().GetSection()
        addr_of_table = symbol.GetStartAddress().GetOffset()
        addr_in_name_table = addr_of_table + (offset * size_of_char)

        error = lldb.SBError()
        types = section.GetSectionData().GetString(error, addr_in_name_table)
        if error.Success():
            return types
        else:
            print("error getting op types: ", error)

    def insn_name_table_offset(self, target, offset):
        tUShort = target.FindFirstType("unsigned short")
        size_of_short = tUShort.GetByteSize()

        symbol = target.FindSymbols("insn_name.y")[0].GetSymbol()
        section = symbol.GetStartAddress().GetSection()
        table_offset = symbol.GetStartAddress().GetOffset()

        table_offset = table_offset + (offset * size_of_short)

        error = lldb.SBError()
        offset = section.GetSectionData().GetUnsignedInt16(error, table_offset)

        if error.Success():
            return offset
        else:
            print("error getting insn name table offset: ", error)

    def insn_name(self, target, process, result, offset):
        symbol = target.FindSymbols("insn_name.x")[0].GetSymbol()
        section = symbol.GetStartAddress().GetSection()
        addr_of_table = symbol.GetStartAddress().GetOffset()

        name_table_offset = self.insn_name_table_offset(target, offset)
        addr_in_name_table = addr_of_table + name_table_offset

        error = lldb.SBError()
        name = section.GetSectionData().GetString(error, addr_in_name_table)

        if error.Success():
            return name
        else:
            print('error getting insn name', error)

def disasm(debugger, command, result, internal_dict):
    disassembler = IseqDissassembler(debugger, command, result, internal_dict)
    frame = disassembler.frame

    if frame.IsValid():
        val = frame.EvaluateExpression(command)
    else:
        val = target.EvaluateExpression(command)
    error = val.GetError()
    if error.Fail():
        print >> result, error
        return

    disassembler.disasm(val);


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand("command script add -f lldb_disasm.disasm rbdisasm")
    print("lldb Ruby disasm installed.")
