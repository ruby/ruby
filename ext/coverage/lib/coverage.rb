require "coverage.so"

module Coverage
  def self.line_stub(file)
    lines = File.foreach(file).map { nil }
    iseqs = [RubyVM::InstructionSequence.compile_file(file)]
    until iseqs.empty?
      iseq = iseqs.pop
      iseq.trace_points.each {|n, _| lines[n - 1] = 0 }
      iseq.each_child {|child| iseqs << child }
    end
    lines
  end
end
