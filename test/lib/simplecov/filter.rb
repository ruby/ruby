module SimpleCov
  #
  # Base filter class. Inherit from this to create custom filters,
  # and overwrite the passes?(source_file) instance method
  #
  # # A sample class that rejects all source files.
  # class StupidFilter < SimpleCov::Filter
  #   def passes?(source_file)
  #     false
  #   end
  # end
  #
  class Filter
    attr_reader :filter_argument
    def initialize(filter_argument)
      @filter_argument = filter_argument
    end

    def matches?(source_file)
      raise "The base filter class is not intended for direct use"
    end

    def passes?(source_file)
      warn "DEPRECATION: SimpleCov::Filter#passes?(x) has been renamed to #matches?. Please update your custom filters accordingly!"
      matches?(source_file)
    end
  end

  class StringFilter < SimpleCov::Filter
    # Returns true when the given source file's filename matches the
    # string configured when initializing this Filter with StringFilter.new('somestring)
    def matches?(source_file)
      (source_file.filename =~ /#{filter_argument}/)
    end
  end

  class BlockFilter < SimpleCov::Filter
    # Returns true if the block given when initializing this filter with BlockFilter.new {|src_file| ... }
    # returns true for the given source file.
    def matches?(source_file)
      filter_argument.call(source_file)
    end
  end
end
