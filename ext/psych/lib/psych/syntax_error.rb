module Psych
  class SyntaxError < ::SyntaxError
    attr_reader :file, :line, :column, :offset, :problem, :context

    def initialize file, line, col, offset, problem, context
      err     = [problem, context].compact.join ' '
      message = "(%s): %s at line %d column %d" % [file, err, line, col]

      @file    = file
      @line    = line
      @column  = col
      @offset  = offset
      @problem = problem
      @context = context
      super(message)
    end
  end
end
