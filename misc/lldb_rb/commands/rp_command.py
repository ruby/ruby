import lldb

from lldb_rb.constants import *
from lldb_rb.utils import *
from lldb_rb.rb_base_command import RbBaseCommand

class RbID2StrCommand(RbBaseCommand):
    program = "rp"

    help_string = "convert and print a Ruby ID to a C string and print it to the LLDB console"

    def call(self, debugger, command, exe_ctx, result):
        val = self.frame.EvaluateExpression(command)
        inspector = RbInspector(debugger, result, self.ruby_globals)
        inspector.inspect(val)
