module ThreadBacktraceLocationSpecs
  class MethodAddedAbsolutePath
    def self.method_added(name)
      ScratchPad.record caller_locations
    end

    def foo
    end
  end
end
