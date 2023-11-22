class LLDBInterface:
    def build_environment(self, debugger):
        self.debugger = debugger
        self.target = debugger.GetSelectedTarget()
        self.process = self.target.GetProcess()
        self.thread = self.process.GetSelectedThread()
        self.frame = self.thread.GetSelectedFrame()
