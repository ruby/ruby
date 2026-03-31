import lldb
import re

from lldb_rb.constants import *
from lldb_rb.rb_base_command import RbBaseCommand

class PrintFlagsCommand(RbBaseCommand):
    program = "print_flags"

    help_string = "Print out the individial flags of an RVALUE object in human readable format"

    # call is where our command logic will be implemented
    def call(self, debugger, command, exe_ctx, result):
        rclass_t = self.target.FindFirstType("::RBasic")
        rcass_ptr = self.target.EvaluateExpression(command).Cast(rclass_t.GetPointerType())
        obj_flags = rcass_ptr.GetValueForExpressionPath("->flags").GetValueAsUnsigned()

        flags = [
            "RUBY_FL_WB_PROTECTED", "RUBY_FL_PROMOTED", "RUBY_FL_FINALIZE",
            "RUBY_FL_SHAREABLE", "RUBY_FL_FREEZE",
            "RUBY_FL_USER0", "RUBY_FL_USER1", "RUBY_FL_USER2", "RUBY_FL_USER3", "RUBY_FL_USER4",
            "RUBY_FL_USER5", "RUBY_FL_USER6", "RUBY_FL_USER7", "RUBY_FL_USER8", "RUBY_FL_USER9",
            "RUBY_FL_USER10", "RUBY_FL_USER11", "RUBY_FL_USER12", "RUBY_FL_USER13", "RUBY_FL_USER14",
            "RUBY_FL_USER15", "RUBY_FL_USER16", "RUBY_FL_USER17", "RUBY_FL_USER18"
        ]

        types_index = {v: k for k, v in self.ruby_globals.items() if re.match(r'RUBY_T_', k)}
        print("TYPE: {}".format(types_index[obj_flags & self.ruby_globals["RUBY_T_MASK"]]))
        for flag in flags:
            output = "{} : {}".format(flag, "1" if (obj_flags & self.ruby_globals[flag]) else "0")
            print(output, file=result)
