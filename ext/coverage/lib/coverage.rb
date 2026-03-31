require "coverage.so"

module Coverage
  # call-seq:
  #   line_stub(file) -> array
  #
  # A simple helper function that creates the "stub" of line coverage
  # from a given source code.
  def self.line_stub(file)
    lines = File.foreach(file).map { nil }
    iseqs = [RubyVM::InstructionSequence.compile_file(file)]
    until iseqs.empty?
      iseq = iseqs.pop
      iseq.trace_points.each {|n, type| lines[n - 1] = 0 if type == :line }
      iseq.each_child {|child| iseqs << child }
    end
    lines
  end
end
