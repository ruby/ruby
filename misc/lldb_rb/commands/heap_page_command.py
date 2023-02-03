import lldb

from lldb_rb.constants import *
from lldb_rb.rb_base_command import RbBaseCommand

class HeapPageCommand(RbBaseCommand):
    program = "heap_page"
    help_string = "prints out 'struct heap_page' for a VALUE pointer in the page"

    def call(self, debugger, command, exe_ctx, result):
        self.t_heap_page_body = self.target.FindFirstType("struct heap_page_body")
        self.t_heap_page_ptr = self.target.FindFirstType("struct heap_page").GetPointerType()

        page = self._get_page(self.frame.EvaluateExpression(command))
        page.Cast(self.t_heap_page_ptr)

        self._append_command_output(debugger, "p (struct heap_page *) %0#x" % page.GetValueAsUnsigned(), result)
        self._append_command_output(debugger, "p *(struct heap_page *) %0#x" % page.GetValueAsUnsigned(), result)

    def _get_page(self, val):
        addr = val.GetValueAsUnsigned()
        page_addr = addr & ~(HEAP_PAGE_ALIGN_MASK)
        address = lldb.SBAddress(page_addr, self.target)
        body = self.target.CreateValueFromAddress("page", address, self.t_heap_page_body)

        return body.GetValueForExpressionPath("->header.page")
