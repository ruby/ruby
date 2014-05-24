# encoding: utf-8

class MockExpectationError < StandardError; end # :nodoc:

##
# A simple and clean mock object framework.

module MiniTest # :nodoc:

  ##
  # All mock objects are an instance of Mock

  class Mock
    alias :__respond_to? :respond_to?

    skip_methods = %w(object_id respond_to_missing? inspect === to_s)

    instance_methods.each do |m|
      undef_method m unless skip_methods.include?(m.to_s) || m =~ /^__/
    end

    def initialize # :nodoc:
      @expected_calls = Hash.new { |calls, name| calls[name] = [] }
      @actual_calls   = Hash.new { |calls, name| calls[name] = [] }
    end

    ##
    # Expect that method +name+ is called, optionally with +args+ or a
    # +blk+, and returns +retval+.
    #
    #   @mock.expect(:meaning_of_life, 42)
    #   @mock.meaning_of_life # => 42
    #
    #   @mock.expect(:do_something_with, true, [some_obj, true])
    #   @mock.do_something_with(some_obj, true) # => true
    #
    #   @mock.expect(:do_something_else, true) do |a1, a2|
    #     a1 == "buggs" && a2 == :bunny
    #   end
    #
    # +args+ is compared to the expected args using case equality (ie, the
    # '===' operator), allowing for less specific expectations.
    #
    #   @mock.expect(:uses_any_string, true, [String])
    #   @mock.uses_any_string("foo") # => true
    #   @mock.verify  # => true
    #
    #   @mock.expect(:uses_one_string, true, ["foo"]
    #   @mock.uses_one_string("bar") # => true
    #   @mock.verify  # => raises MockExpectationError

    def expect(name, retval, args=[], &blk)
      if block_given?
        raise ArgumentError, "args ignored when block given" unless args.empty?
        @expected_calls[name] << { :retval => retval, :block => blk }
      else
        raise ArgumentError, "args must be an array" unless Array === args
        @expected_calls[name] << { :retval => retval, :args => args }
      end
      self
    end

    def __call name, data # :nodoc:
      case data
      when Hash then
        "#{name}(#{data[:args].inspect[1..-2]}) => #{data[:retval].inspect}"
      else
        data.map { |d| __call name, d }.join ", "
      end
    end

    ##
    # Verify that all methods were called as expected. Raises
    # +MockExpectationError+ if the mock object was not called as
    # expected.

    def verify
      @expected_calls.each do |name, calls|
        calls.each do |expected|
          msg1 = "expected #{__call name, expected}"
          msg2 = "#{msg1}, got [#{__call name, @actual_calls[name]}]"

          raise MockExpectationError, msg2 if
            @actual_calls.has_key?(name) and
            not @actual_calls[name].include?(expected)

          raise MockExpectationError, msg1 unless
            @actual_calls.has_key?(name) and
            @actual_calls[name].include?(expected)
        end
      end
      true
    end

    def method_missing(sym, *args) # :nodoc:
      unless @expected_calls.has_key?(sym) then
        raise NoMethodError, "unmocked method %p, expected one of %p" %
          [sym, @expected_calls.keys.sort_by(&:to_s)]
      end

      index = @actual_calls[sym].length
      expected_call = @expected_calls[sym][index]

      unless expected_call then
        raise MockExpectationError, "No more expects available for %p: %p" %
          [sym, args]
      end

      expected_args, retval, val_block =
        expected_call.values_at(:args, :retval, :block)

      if val_block then
        raise MockExpectationError, "mocked method %p failed block w/ %p" %
          [sym, args] unless val_block.call(args)

        # keep "verify" happy
        @actual_calls[sym] << expected_call
        return retval
      end

      if expected_args.size != args.size then
        raise ArgumentError, "mocked method %p expects %d arguments, got %d" %
          [sym, expected_args.size, args.size]
      end

      fully_matched = expected_args.zip(args).all? { |mod, a|
        mod === a or mod == a
      }

      unless fully_matched then
        raise MockExpectationError, "mocked method %p called with unexpected arguments %p" %
          [sym, args]
      end

      @actual_calls[sym] << {
        :retval => retval,
        :args => expected_args.zip(args).map { |mod, a| mod === a ? mod : a }
      }

      retval
    end

    def respond_to?(sym, include_private = false) # :nodoc:
      return true if @expected_calls.has_key?(sym.to_sym)
      return __respond_to?(sym, include_private)
    end
  end
end

class Object # :nodoc:

  ##
  # Add a temporary stubbed method replacing +name+ for the duration
  # of the +block+. If +val_or_callable+ responds to #call, then it
  # returns the result of calling it, otherwise returns the value
  # as-is. Cleans up the stub at the end of the +block+. The method
  # +name+ must exist before stubbing.
  #
  #     def test_stale_eh
  #       obj_under_test = Something.new
  #       refute obj_under_test.stale?
  #
  #       Time.stub :now, Time.at(0) do
  #         assert obj_under_test.stale?
  #       end
  #     end

  def stub name, val_or_callable, &block
    new_name = "__minitest_stub__#{name}"

    metaclass = class << self; self; end

    if respond_to? name and not methods.map(&:to_s).include? name.to_s then
      metaclass.send :define_method, name do |*args|
        super(*args)
      end
    end

    metaclass.send :alias_method, new_name, name

    metaclass.send :define_method, name do |*args|
      if val_or_callable.respond_to? :call then
        val_or_callable.call(*args)
      else
        val_or_callable
      end
    end

    yield self
  ensure
    metaclass.send :undef_method, name
    metaclass.send :alias_method, name, new_name
    metaclass.send :undef_method, new_name
  end
end
