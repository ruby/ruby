# :nodoc:
#
# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit/assertionfailederror'

module Test # :nodoc:
  module Unit # :nodoc:

    # Contains all of the standard Test::Unit assertions. Mixed in
    # to Test::Unit::TestCase. To mix it in and use its
    # functionality, you simply need to rescue
    # Test::Unit::AssertionFailedError, and you can additionally
    # override add_assertion to be notified whenever an assertion
    # is made.
    #
    # Notes:
    # * The message to each assertion, if given, will be
    #   propagated with the failure.
    # * It's easy to add your own assertions based on assert_block().
    module Assertions

      # The assertion upon which all other assertions are
      # based. Passes if the block yields true.
      public
      def assert_block(message="") # :yields: 
        _wrap_assertion do
          if (! yield)
            raise AssertionFailedError.new(message.to_s)
          end
        end
      end

      # Passes if boolean is true.
      public
      def assert(boolean, message="")
        _wrap_assertion do
          assert_block("assert should not be called with a block.") { !block_given? }
          assert_block(message) { boolean }
        end
      end

      # Passes if expected == actual. Note that the ordering of
      # arguments is important, since a helpful error message is
      # generated when this one fails that tells you the values
      # of expected and actual.
      public
      def assert_equal(expected, actual, message=nil)
        full_message = build_message(message, expected, actual) do |arg1, arg2|
          "<#{arg1}> expected but was\n" +
          "<#{arg2}>"
        end
        assert_block(full_message) { expected == actual }
      end

      # Passes if block raises exception.
      public
      def assert_raises(expected_exception_klass, message="")
        _wrap_assertion do
          assert_instance_of(Class, expected_exception_klass, "Should expect a class of exception")
          actual_exception = nil
          full_message = build_message(message, expected_exception_klass) do |arg|
            "<#{arg}> exception expected but none was thrown"
          end
          assert_block(full_message) do
            thrown = false
            begin
              yield
            rescue Exception => thrown_exception
              actual_exception = thrown_exception
              thrown = true
            end
            thrown
          end
          full_message = build_message(message, expected_exception_klass, actual_exception) do |arg1, arg2|
            "<#{arg1}> exception expected but was\n" +
            arg2
          end
          assert_block(full_message) { expected_exception_klass == actual_exception.class }
          actual_exception
        end
      end

      # Passes if object.class == klass.
      public
      def assert_instance_of(klass, object, message="")
        _wrap_assertion do
          assert_equal(Class, klass.class, "assert_instance_of takes a Class as its first argument")
          full_message = build_message(message, object, klass, object.class) do |arg1, arg2, arg3|
            "<#{arg1}> expected to be an instance of\n" + 
            "<#{arg2}> but was\n" +
            "<#{arg3}>"
          end
          assert_block(full_message) { klass == object.class }
        end
      end

      # Passes if object.nil?.
      public
      def assert_nil(object, message="")
        assert_equal(nil, object, message)
      end

      # Passes if object.kind_of?(klass).
      public
      def assert_kind_of(klass, object, message="")
        _wrap_assertion do
          assert(klass.kind_of?(Module), "The first parameter to assert_kind_of should be a kind_of Module.")
          full_message = build_message(message, object, klass) do |arg1, arg2|
            "<#{arg1}>\n" +
            "expected to be kind_of?<#{arg2}>"
          end
          assert_block(full_message) { object.kind_of?(klass) }
        end
      end

      # Passes if object.respond_to?(method) is true.
      public
      def assert_respond_to(object, method, message="")
        _wrap_assertion do
          assert(method.kind_of?(Symbol) || method.kind_of?(String), "The method argument to #assert_respond_to should be specified as a Symbol or a String.")
          full_message = build_message(message, object, object.class, method) do |arg1, arg2, arg3|
            "<#{arg1}>\n" +
            "of type <#{arg2}>\n" +
            "expected to respond_to?<#{arg3}>"
          end
          assert_block(full_message) { object.respond_to?(method) }
        end
      end

      # Passes if string =~ pattern.
      public
      def assert_match(pattern, string, message="")
        _wrap_assertion do
          full_message = build_message(message, string, pattern) do |arg1, arg2|
            "<#{arg1}> expected to be =~\n" +
            "<#{arg2}>"
          end
          assert_block(full_message) { string =~ pattern }
        end
      end

      # Passes if actual.equal?(expected) (i.e. they are the
      # same instance).
      public
      def assert_same(expected, actual, message="")
        full_message = build_message(message, expected, expected.__id__, actual, actual.__id__) do |arg1, arg2, arg3, arg4|
          "<#{arg1}:#{arg2}> expected to be equal? to\n" +
          "<#{arg3}:#{arg4}>"
        end
        assert_block(full_message) { actual.equal?(expected) }
      end

      # Compares the two objects based on the passed
      # operator. Passes if object1.send(operator, object2) is
      # true.
      public
      def assert_operator(object1, operator, object2, message="")
        full_message = build_message(message, object1, operator, object2) do |arg1, arg2, arg3|
          "<#{arg1}> expected to be\n" +
          "#{arg2}\n" +
          "<#{arg3}>"
        end
        assert_block(full_message) { object1.send(operator, object2) }
      end

      # Passes if block does not raise an exception.
      public
      def assert_nothing_raised(*args)
        _wrap_assertion do
          message = ""
          if (!args[-1].instance_of?(Class))
            message = args.pop
          end
          begin
            yield
          rescue Exception => thrown_exception
            if (args.empty? || args.include?(thrown_exception.class))
              full_message = build_message(message, thrown_exception) do |arg1|
                "Exception raised:\n" +
                arg1
              end
              flunk(full_message)
            else
              raise thrown_exception.class, thrown_exception.message, thrown_exception.backtrace
            end
          end
          nil
        end
      end

      # Always fails.
      public
      def flunk(message="")
        assert(false, message)
      end

      # Passes if !actual.equal?(expected).
      public
      def assert_not_same(expected, actual, message="")
        full_message = build_message(message, expected, expected.__id__, actual, actual.__id__) do |arg1, arg2, arg3, arg4|
          "<#{arg1}:#{arg2}> expected to not be equal? to\n" +
          "<#{arg3}:#{arg4}>"
        end
        assert_block(full_message) { !actual.equal?(expected) }
      end

      # Passes if expected != actual.
      public
      def assert_not_equal(expected, actual, message="")
        full_message = build_message(message, expected, actual) do |arg1, arg2|
          "<#{arg1}> expected to be != to\n" +
          "<#{arg2}>"
        end
        assert_block(full_message) { expected != actual }
      end

      # Passes if !object.nil?.
      public
      def assert_not_nil(object, message="")
        full_message = build_message(message, object) do |arg|
          "<#{arg}> expected to not be nil"
        end
        assert_block(full_message) { !object.nil? }
      end

      # Passes if string !~ regularExpression.
      public
      def assert_no_match(regexp, string, message="")
        _wrap_assertion do
          assert_instance_of(Regexp, regexp, "The first argument to assert_does_not_match should be a Regexp.")
          full_message = build_message(message, regexp.source, string) do |arg1, arg2|
            "</#{arg1}/> expected to not match\n" +
            " <#{arg2}>"
          end
          assert_block(full_message) { regexp !~ string }
        end
      end

      # Passes if block throws symbol.
      public
      def assert_throws(expected_symbol, message="", &proc)
        _wrap_assertion do
          assert_instance_of(Symbol, expected_symbol, "assert_throws expects the symbol that should be thrown for its first argument")
          assert(block_given?, "Should have passed a block to assert_throws")
          caught = true
          begin
            catch(expected_symbol) do
              proc.call
              caught = false
            end
            full_message = build_message(message, expected_symbol) do |arg|
              "<:#{arg}> should have been thrown"
            end
            assert(caught, full_message)
          rescue NameError => name_error
            if ( name_error.message !~ /^uncaught throw `(.+)'$/ )  #`
              raise name_error
            end
            full_message = build_message(message, expected_symbol, $1) do |arg1, arg2|
              "<:#{arg1}> expected to be thrown but\n" +
              "<:#{arg2}> was thrown"
            end
            flunk(full_message)
          end  
        end
      end

      # Passes if block does not throw anything.
      public
      def assert_nothing_thrown(message="", &proc)
        _wrap_assertion do
          assert(block_given?, "Should have passed a block to assert_nothing_thrown")
          begin
            proc.call
          rescue NameError => name_error
            if (name_error.message !~ /^uncaught throw `(.+)'$/ )  #`
              raise name_error
            end
            full_message = build_message(message, $1) do |arg|
              "<:#{arg}> was thrown when nothing was expected"
            end
            flunk(full_message)
          end
          full_message = build_message(message) { || "Expected nothing to be thrown" }
          assert(true, full_message)
        end
      end

      # Passes if expected_float and actual_float are equal
      # within delta tolerance.
      public
      def assert_in_delta(expected_float, actual_float, delta, message="")
        _wrap_assertion do
          {expected_float => "first float", actual_float => "second float", delta => "delta"}.each do |float, name|
            assert_respond_to(float, :to_f, "The arguments must respond to to_f; the #{name} did not")
          end
          assert_operator(delta, :>=, 0.0, "The delta should not be negative")
          full_message = build_message(message, expected_float, actual_float, delta) do |arg1, arg2, arg3|
            "<#{arg1}> and\n" +
            "<#{arg2}> expected to be within\n" +
            "<#{arg3}> of each other"
          end
          assert_block(full_message) { (expected_float.to_f - actual_float.to_f).abs <= delta.to_f }
        end
      end

      # Passes if the method sent returns a true value.
      public
      def assert_send(send_array, message="")
        _wrap_assertion do
          assert_instance_of(Array, send_array, "assert_send requires an array of send information")
          assert(send_array.size >= 2, "assert_send requires at least a receiver and a message name")
          full_message = build_message(message, send_array[0], send_array[1], send_array[2..-1]) do |arg1, arg2, arg3|
            "<#{arg1}> expected to respond to\n" +
            "<#{arg2}(#{arg3})> with true"
          end
          assert_block(full_message) { send_array[0].__send__(send_array[1], *send_array[2..-1]) }
        end
      end

      public
      def build_message(message, *arguments, &block) # :nodoc:
        return AssertionMessage.new(message.to_s, arguments, block)
      end

      private
      def _wrap_assertion # :nodoc:
        @_assertion_wrapped ||= false
        unless (@_assertion_wrapped)
          @_assertion_wrapped = true
          begin
            add_assertion
            return yield
          ensure
            @_assertion_wrapped = false
          end
        else
          return yield
        end
      end
      
      # Called whenever an assertion is made.
      private
      def add_assertion
      end
      
      class AssertionMessage # :nodoc: all
        def self.convert(object)
          case object
            when String
              return object
            when Symbol
              return object.to_s
            when Regexp
              return "/#{object.source}/"
            when Exception
              return "Class: <#{object.class}>\n" +
                  "Message: <#{object.message}>\n" +
                  "---Backtrace---\n" +
                  object.backtrace.join("\n") + "\n" +
                  "---------------"
            else
              return object.inspect
          end
        end
        
        def initialize(message, parameters, block)
          @message = message
          @parameters = parameters
          @block = block
        end
        
        def to_s
          message_parts = []
          if (@message != nil && @message != "")
            if (@message !~ /\.$/)
              @message << "."
            end
            message_parts << @message
          end
          @parameters = @parameters.collect {
            | parameter |
            self.class.convert(parameter)
          }
          message_parts << @block.call(*@parameters)
          return message_parts.join("\n")
        end
      end
    end
  end
end
