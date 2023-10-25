import lldb
from pydoc import locate
from lldb_rb.constants import *
from lldb_rb.utils import *

class RbBaseCommand(LLDBInterface):
    @classmethod
    def register_lldb_command(cls, debugger, module_name):
        # Add any commands contained in this module to LLDB
        command = f"command script add -c {module_name}.{cls.__name__} {cls.program}"
        debugger.HandleCommand(command)

    @classmethod
    def lldb_init(cls, debugger):
        target = debugger.GetSelectedTarget()
        global SIZEOF_VALUE
        SIZEOF_VALUE = target.FindFirstType("VALUE").GetByteSize()

        value_types = []
        g = globals()

        imemo_types = target.FindFirstType("enum imemo_type")

        #for member in imemo_types.GetEnumMembers():
        #    g[member.GetName()] = member.GetValueAsUnsigned()

        for enum in target.FindFirstGlobalVariable("ruby_dummy_gdb_enums"):
            enum = enum.GetType()
            members = enum.GetEnumMembers()
            for i in range(0, members.GetSize()):
                member = members.GetTypeEnumMemberAtIndex(i)
                name = member.GetName()
                value = member.GetValueAsUnsigned()
                g[name] = value

                if name.startswith("RUBY_T_"):
                    value_types.append(name)
        g["value_types"] = value_types
        return g

    def __init__(self, debugger, _internal_dict):
        self.ruby_globals = RbBaseCommand.lldb_init(debugger)
        self.internal_dict = _internal_dict

    def __call__(self, debugger, command, exe_ctx, result):
        self.ruby_globals = RbBaseCommand.lldb_init(debugger)
        self.build_environment(debugger)
        self.call(debugger, command, exe_ctx, result)

    def call(self, debugger, command, exe_ctx, result):
        raise NotImplementedError("subclasses must implement call")

    def get_short_help(self):
        return self.__class__.help_string

    def get_long_help(self):
        return self.__class__.help_string
