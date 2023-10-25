# This is a command template for implementing a helper function inside LLDB. To
# use this file
#   1. Copy it and rename the copy so it ends with `_command.py`.
#   2. Rename the class to something descriptive that ends with Command.
#   3. Change the program variable to be a descriptive command name
#   4. Ensure you are inheriting from RbBaseCommand or another command that
#      implements the same interface

import lldb

from lldb_rb.constants import *
from lldb_rb.rb_base_command import RbBaseCommand

# This test command inherits from RbBaseCommand which provides access to Ruby
# globals and utility helpers
class TestCommand(RbBaseCommand):
    # program is the keyword the user will type in lldb to execute this command
    program = "test"

    # help_string will be displayed in lldb when the user uses the help functions
    help_string = "This is a test command to show how to implement lldb commands"

    # call is where our command logic will be implemented
    def call(self, debugger, command, exe_ctx, result):
        # This method will be called once the LLDB environment has been setup.
        # You will have access to self.target, self.process, self.frame, and
        # self.thread
        #
        # This is where we should implement our command logic
        pass
