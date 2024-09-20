import lldb
from lldb_rb.lldb_interface import LLDBInterface
from lldb_rb.constants import *

class HeapPage(LLDBInterface):
    def __init__(self, debugger, val):
        self.build_environment(debugger)
        self.page_type = self.target.FindFirstType("struct heap_page").GetPointerType()
        self.val = val

    def heap_page_body(self, command, ctx, result, internal_dict):
        process = self.target.GetProcess()
        thread = process.GetSelectedThread()
        frame = thread.GetSelectedFrame()

        val = frame.EvaluateExpression(command)
        page = self.get_page_body(val)
        print("Page body address: ", page.GetAddress(), file=result)
        print(page, file=result)

    def get_page_body(self, val):
        tHeapPageBody = self.target.FindFirstType("struct heap_page_body")
        addr = val.GetValueAsUnsigned()
        page_addr = addr & ~(HEAP_PAGE_ALIGN_MASK)
        address = lldb.SBAddress(page_addr, self.target)
        return self.target.CreateValueFromAddress("page", address, tHeapPageBody)

    def get_page_raw(self, val):
        body = self.get_page_body(val)
        return body.GetValueForExpressionPath("->header.page")

    def to_heap_page_struct(self):
        pagePtr = self.get_page_raw(self.val)
        return pagePtr.Cast(self.page_type)


class RbObject(LLDBInterface):
    def __init__(self, ptr, debugger, ruby_globals):
        self.build_environment(debugger)
        self.ruby_globals = ruby_globals

        self.flUser1 = self.ruby_globals["RUBY_FL_USER1"]
        self.flUser2 = self.ruby_globals["RUBY_FL_USER2"]
        self.flUser3 = self.ruby_globals["RUBY_FL_USER3"]
        self.flUser4 = self.ruby_globals["RUBY_FL_USER4"]
        self.flUser5 = self.ruby_globals["RUBY_FL_USER5"]
        self.flUser6 = self.ruby_globals["RUBY_FL_USER6"]
        self.flUser7 = self.ruby_globals["RUBY_FL_USER7"]
        self.flUser8 = self.ruby_globals["RUBY_FL_USER8"]
        self.flUser9 = self.ruby_globals["RUBY_FL_USER9"]
        self.flUshift = self.ruby_globals["RUBY_FL_USHIFT"]

        self.tRBasic = self.target.FindFirstType("struct RBasic").GetPointerType()
        self.tRValue = self.target.FindFirstType("struct RVALUE")

        self.val = ptr.Cast(self.tRBasic)
        self.page = HeapPage(self.debugger, self.val)
        self.flags = self.val.GetValueForExpressionPath("->flags").GetValueAsUnsigned()

        self.type = None
        self.type_name = ""

    def check_bits(self, bitmap_name, bitmap_index, bitmap_bit, v):
        page = self.page.to_heap_page_struct()
        bits = page.GetChildMemberWithName(bitmap_name)
        plane = bits.GetChildAtIndex(bitmap_index).GetValueAsUnsigned()
        if (plane & bitmap_bit) != 0:
            return v
        else:
            return ' '

    def dump_bits(self, result, end = "\n"):
        tRValue = self.target.FindFirstType("struct RVALUE")
        tUintPtr = self.target.FindFirstType("uintptr_t") # bits_t

        num_in_page = (self.val.GetValueAsUnsigned() & HEAP_PAGE_ALIGN_MASK) // tRValue.GetByteSize();
        bits_bitlength = tUintPtr.GetByteSize() * 8
        bitmap_index = num_in_page // bits_bitlength
        bitmap_offset = num_in_page & (bits_bitlength - 1)
        bitmap_bit = 1 << bitmap_offset

        page = self.page.to_heap_page_struct()
        print("bits: [%s%s%s%s%s]" % (
            self.check_bits("uncollectible_bits", bitmap_index, bitmap_bit, "L"),
            self.check_bits("mark_bits", bitmap_index, bitmap_bit, "M"),
            self.check_bits("pinned_bits", bitmap_index, bitmap_bit, "P"),
            self.check_bits("marking_bits", bitmap_index, bitmap_bit, "R"),
            self.check_bits("wb_unprotected_bits", bitmap_index, bitmap_bit, "U"),
            ), end=end, file=result)

    def promoted_p(self):
        rbFlPromoted = self.ruby_globals["RUBY_FL_PROMOTED"]
        return (self.flags & rbFlPromoted) == rbFlPromoted

    def frozen_p(self):
        rbFlFreeze = self.ruby_globals["RUBY_FL_FREEZE"]
        return (self.flags & rbFlFreeze) == rbFlFreeze

    def is_type(self, type_name):
        if self.type is None:
            flTMask = self.ruby_globals["RUBY_T_MASK"]
            flType = self.flags & flTMask
            self.type = flType

        if self.type == self.ruby_globals[type_name]:
            self.type_name = type_name
            return True
        else:
            return False

    def as_type(self, type_name):
        return self.val.Cast(self.tRValue.GetPointerType()).GetValueForExpressionPath("->as."+type_name)

    def ary_ptr(self):
        rval = self.as_type("array")
        if self.flags & self.ruby_globals["RUBY_FL_USER1"]:
            ptr = rval.GetValueForExpressionPath("->as.ary")
        else:
            ptr = rval.GetValueForExpressionPath("->as.heap.ptr")
        return ptr

    def ary_len(self):
        if self.flags & self.flUser1:
            len = ((self.flags &
              (self.flUser3 | self.flUser4 | self.flUser5 | self.flUser6 |
               self.flUser7 | self.flUser8 | self.flUser9)
              ) >> (self.flUshift + 3))
        else:
            rval = self.as_type("array")
            len = rval.GetValueForExpressionPath("->as.heap.len").GetValueAsSigned()

        return len

    def bignum_len(self):
        if self.flags & self.flUser2:
            len = ((self.flags &
              (self.flUser3 | self.flUser4 | self.flUser5)
              ) >> (self.flUshift + 3))
        else:
            len = (self.as_type("bignum").GetValueForExpressionPath("->as.heap.len").
                   GetValueAsUnsigned())

        return len
