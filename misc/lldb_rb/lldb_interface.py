class LLDBInterface:
    def build_environment(self, debugger):
        self.debugger = debugger
        self.target = debugger.GetSelectedTarget()
        self.process = self.target.GetProcess()
        self.thread = self.process.GetSelectedThread()
        self.frame = self.thread.GetSelectedFrame()

    def _append_command_output(self, command):
        output1 = self.result.GetOutput()
        self.debugger.GetCommandInterpreter().HandleCommand(command, self.result)
        output2 = self.result.GetOutput()
        self.result.Clear()
        self.result.write(output1)
        self.result.write(output2)

    def _append_expression(self, expression):
        self._append_command_output("expression " + expression)
