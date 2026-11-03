require 'stringio'

module ARGFSpecs
  # An object that is not an IO, for assigning to $stdin. It reads from a
  # StringIO and records the arguments and keywords each method receives.
  class Stdin
    attr_reader :calls

    def initialize(string)
      @io = StringIO.new(string)
      @calls = []
    end

    def gets(*args, **kw)
      @calls << [:gets, args, kw]
      @io.gets(*args, **kw)
    end

    def each_line(*args, **kw, &block)
      @calls << [:each_line, args, kw]
      @io.each_line(*args, **kw, &block)
      self
    end

    def each(*args, **kw, &block)
      @calls << [:each, args, kw]
      @io.each(*args, **kw, &block)
      self
    end

    def readlines(*args, **kw)
      @calls << [:readlines, args, kw]
      @io.readlines(*args, **kw)
    end

    def to_a(*args, **kw)
      @calls << [:to_a, args, kw]
      @io.to_a(*args, **kw)
    end
  end
end
