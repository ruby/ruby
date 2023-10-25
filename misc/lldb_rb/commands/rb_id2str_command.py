import lldb

from lldb_rb.constants import *
from lldb_rb.utils import *
from lldb_rb.rb_base_command import RbBaseCommand

class RbID2StrCommand(RbBaseCommand):
    program = "rb_id2str"

    help_string = "convert and print a Ruby ID to a C string and print it to the LLDB console"

    def call(self, debugger, command, exe_ctx, result):
        global_symbols = self.target.FindFirstGlobalVariable("ruby_global_symbols")

        id_val = self.frame.EvaluateExpression(command).GetValueAsUnsigned()
        num = self.rb_id_to_serial(id_val)

        last_id = global_symbols.GetChildMemberWithName("last_id").GetValueAsUnsigned()
        ID_ENTRY_SIZE = 2
        ID_ENTRY_UNIT = int(self.target.FindFirstGlobalVariable("ID_ENTRY_UNIT").GetValue())

        ids = global_symbols.GetChildMemberWithName("ids")

        if num <= last_id:
            idx = num // ID_ENTRY_UNIT
            ary = self.rb_ary_entry(ids, idx, result)
            pos = (num % ID_ENTRY_UNIT) * ID_ENTRY_SIZE
            id_str = self.rb_ary_entry(ary, pos, result)

            RbInspector(debugger, result, self.ruby_globals).inspect(id_str)

    def rb_id_to_serial(self, id_val):
        if id_val > self.ruby_globals["tLAST_OP_ID"]:
            return id_val >> self.ruby_globals["RUBY_ID_SCOPE_SHIFT"]
        else:
            return id_val

    def rb_ary_entry(self, ary, idx, result):
        tRArray = self.target.FindFirstType("struct RArray").GetPointerType()
        ary = ary.Cast(tRArray)
        flags = ary.GetValueForExpressionPath("->flags").GetValueAsUnsigned()

        if flags & self.ruby_globals["RUBY_FL_USER1"]:
            ptr = ary.GetValueForExpressionPath("->as.ary")
        else:
            ptr = ary.GetValueForExpressionPath("->as.heap.ptr")

        ptr_addr = ptr.GetValueAsUnsigned() + (idx * ptr.GetType().GetByteSize())
        return self.target.CreateValueFromAddress("ary_entry[%d]" % idx, lldb.SBAddress(ptr_addr, self.target), ptr.GetType().GetPointeeType())
