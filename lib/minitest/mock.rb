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
      n, r = name, retval # for the closure below
      @expected_calls[name] = { :retval => retval, :args => args }
      self.class.__send__ :remove_method, name if respond_to? name
      self.class.__send__(:define_method, name) { |*x|
        raise ArgumentError unless @expected_calls[n][:args].size == x.size
        @actual_calls[n] << { :retval => r, :args => x }
        retval
      }
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
  end
end
