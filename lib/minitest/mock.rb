############################################################
# This file is imported from a different project.
# DO NOT make modifications in this repo.
# File a patch instead and assign it to Ryan Davis
############################################################

class MockExpectationError < StandardError; end

module MiniTest
  class Mock
    def initialize
      @expected_calls = {}
      @actual_calls = Hash.new {|h,k| h[k] = [] }
    end

    def expect(name, retval, args=[])
      @expected_calls[name] = { :retval => retval, :args => args }
      self
    end

    def verify
      @expected_calls.each_key do |name|
        expected = @expected_calls[name]
        msg = "expected #{name}, #{expected.inspect}"
        raise MockExpectationError, msg unless
          @actual_calls.has_key? name and @actual_calls[name].include?(expected)
      end
      true
    end

    def method_missing(sym, *args)
      raise NoMethodError unless @expected_calls.has_key?(sym)
      raise ArgumentError unless @expected_calls[sym][:args].size == args.size
      retval = @expected_calls[sym][:retval]
      @actual_calls[sym] << { :retval => retval, :args => args }
      retval
    end

    alias :original_respond_to? :respond_to?
    def respond_to?(sym)
      return true if @expected_calls.has_key?(sym)
      return original_respond_to?(sym)
    end
  end
end
