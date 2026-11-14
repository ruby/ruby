assert_equal '[[:end, 5], [:return, 4]]', %q{
  events = []
  trace = TracePoint.new(:end, :return) do |event|
    events << [event.event, event.lineno] if event.path == 'parsey-trace.rb'
  end
  code = RubyVM::InstructionSequence.compile_parsey(<<~'RUBY', 'parsey-trace.rb')
    class ParseyTraceLocation
      def value
        1
      end
    end
    ParseyTraceLocation.new.value
  RUBY
  trace.enable { code.eval }
  events.inspect
}

assert_equal '1', %q{
  RubyVM::InstructionSequence.compile_parsey(<<~'RUBY').eval
    def parsey_rescue_location
      raise
    rescue
      caller_locations(1, 1)[0]
    end
    parsey_rescue_location.lineno
  RUBY
}

assert_equal '[[1], [1, 2, 3], [1, 2]]', %q{
  sources = [
    "value = \"#{'#{'}\nObject.new\n}\"",
    "value = \"#{'#{'}\nObject.new;\nObject.new\n}\"",
    "value = \"#{'#{'};\nObject.new\n}\""
  ]
  sources.map do |source|
    events = []
    code = RubyVM::InstructionSequence.compile_parsey(source, 'interpolation.rb')
    TracePoint.new(:line) do |event|
      events << event.lineno if event.path == 'interpolation.rb'
    end.enable { code.eval }
    events
  end.inspect
}

assert_equal '[[["rescue in foo", 1]], [["ensure in foo", 6]]]', %q{
  sources = [
    "def foo\n begin\n rescue\n  p :rescue\n end\nend",
    "def foo\n begin\n  p :body\n ensure\n  begin\n   p :ensure\n  end\n end\nend"
  ]
  sources.map do |source|
    handlers = []
    RubyVM::InstructionSequence.compile_parsey(source).each_child do |method|
      method.each_child { |handler| handlers << [handler.label, handler.first_lineno] }
    end
    handlers
  end.inspect
}
