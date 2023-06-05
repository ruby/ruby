from lldb_rb.rb_base_command import RbBaseCommand

class RclassExtCommand(RbBaseCommand):
    program = "rclass_ext"
    help_string = "retrieves and prints the rb_classext_struct for the VALUE pointer passed in"

    def call(self, debugger, command, exe_ctx, result):
        uintptr_t = self.target.FindFirstType("uintptr_t")
        rclass_t = self.target.FindFirstType("struct RClass")
        rclass_ext_t = self.target.FindFirstType("rb_classext_t")

        rclass_addr = self.target.EvaluateExpression(command).Cast(uintptr_t)
        rclass_ext_addr = (rclass_addr.GetValueAsUnsigned() + rclass_t.GetByteSize())
        debugger.HandleCommand("p *(rb_classext_t *)%0#x" % rclass_ext_addr)
