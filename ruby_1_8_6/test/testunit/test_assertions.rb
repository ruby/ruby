# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit'

module Test
  module Unit
    class TC_Assertions < TestCase
      def check(value, message="")
        add_assertion
        if (!value)
          raise AssertionFailedError.new(message)
        end
      end

      def check_assertions(expect_fail, expected_message="", return_value_expected=false)
        @actual_assertion_count = 0
        failed = true
        actual_message = nil
        @catch_assertions = true
        return_value = nil
        begin
          return_value = yield
          failed = false
        rescue AssertionFailedError => error
          actual_message = error.message
        end
        @catch_assertions = false
        check(expect_fail == failed, (expect_fail ? "Should have failed, but didn't" : "Should not have failed, but did with message\n<#{actual_message}>"))
        check(1 == @actual_assertion_count, "Should have made one assertion but made <#{@actual_assertion_count}>")
        if (expect_fail)
          case expected_message
            when String
              check(actual_message == expected_message, "Should have the correct message.\n<#{expected_message.inspect}> expected but was\n<#{actual_message.inspect}>")
            when Regexp
              check(actual_message =~ expected_message, "The message should match correctly.\n</#{expected_message.source}/> expected to match\n<#{actual_message.inspect}>")
            else
              check(false, "Incorrect expected message type in assert_nothing_failed")
          end
        else
          if (!return_value_expected)
            check(return_value.nil?, "Should not return a value but returned <#{return_value}>")
          else
            check(!return_value.nil?, "Should return a value")
          end
        end
        return return_value
      end
      
      def check_nothing_fails(return_value_expected=false, &proc)
        check_assertions(false, "", return_value_expected, &proc)
      end
      
      def check_fails(expected_message="", &proc)
        check_assertions(true, expected_message, &proc)
      end
      
      def test_assert_block
        check_nothing_fails {
          assert_block {true}
        }
        check_nothing_fails {
          assert_block("successful assert_block") {true}
        }
        check_nothing_fails {
          assert_block("successful assert_block") {true}
        }
        check_fails("assert_block failed.") {
          assert_block {false}
        }
        check_fails("failed assert_block") {
          assert_block("failed assert_block") {false}
        }
      end
      
      def test_assert
        check_nothing_fails{assert("a")}
        check_nothing_fails{assert(true)}
        check_nothing_fails{assert(true, "successful assert")}
        check_fails("<nil> is not true."){assert(nil)}
        check_fails("<false> is not true."){assert(false)}
        check_fails("failed assert.\n<false> is not true."){assert(false, "failed assert")}
      end
      
      def test_assert_equal
        check_nothing_fails {
          assert_equal("string1", "string1")
        }
        check_nothing_fails {
          assert_equal( "string1", "string1", "successful assert_equal")
        }
        check_nothing_fails {
          assert_equal("string1", "string1", "successful assert_equal")
        }
        check_fails(%Q{<"string1"> expected but was\n<"string2">.}) {
          assert_equal("string1", "string2")
        }
        check_fails(%Q{failed assert_equal.\n<"string1"> expected but was\n<"string2">.}) {
          assert_equal("string1", "string2", "failed assert_equal")
        }
        check_fails(%Q{<"1"> expected but was\n<1>.}) do
          assert_equal("1", 1)
        end
      end
      
      def test_assert_raise
        return_value = nil
        check_nothing_fails(true) {
          return_value = assert_raise(RuntimeError) {
            raise "Error"
          }
        }
        check(return_value.kind_of?(Exception), "Should have returned the exception from a successful assert_raise")
        check(return_value.message == "Error", "Should have returned the correct exception from a successful assert_raise")
        check_nothing_fails(true) {
          assert_raise(ArgumentError, "successful assert_raise") {
            raise ArgumentError.new("Error")
          }
        }
        check_nothing_fails(true) {
          assert_raise(RuntimeError) {
            raise "Error"
          }
        }
        check_nothing_fails(true) {
          assert_raise(RuntimeError, "successful assert_raise") {
            raise "Error"
          }
        }
        check_fails("<RuntimeError> exception expected but none was thrown.") {
          assert_raise(RuntimeError) {
            1 + 1
          }
        }
        check_fails(%r{\Afailed assert_raise.\n<ArgumentError> exception expected but was\nClass: <RuntimeError>\nMessage: <"Error">\n---Backtrace---\n.+\n---------------\Z}m) {
          assert_raise(ArgumentError, "failed assert_raise") {
            raise "Error"
          }
        }
        check_fails("Should expect a class of exception, Object.\n<false> is not true.") {
          assert_nothing_raised(Object) {
            1 + 1
          }
        }

        exceptions = [ArgumentError, TypeError]
        modules = [Math, Comparable]
        rescues = exceptions + modules
        exceptions.each do |exc|
          check_nothing_fails(true) {
            return_value = assert_raise(*rescues) {
              raise exc, "Error"
            }
          }
          check(return_value.instance_of?(exc), "Should have returned #{exc} but was #{return_value.class}")
          check(return_value.message == "Error", "Should have returned the correct exception from a successful assert_raise")
        end
        modules.each do |mod|
          check_nothing_fails(true) {
            return_value = assert_raise(*rescues) {
              raise Exception.new("Error").extend(mod)
            }
          }
          check(mod === return_value, "Should have returned #{mod}")
          check(return_value.message == "Error", "Should have returned the correct exception from a successful assert_raise")
        end
        check_fails("<[ArgumentError, TypeError, Math, Comparable]> exception expected but none was thrown.") {
          assert_raise(*rescues) {
            1 + 1
          }
        }
        check_fails(%r{\Afailed assert_raise.
<\[ArgumentError, TypeError\]> exception expected but was
Class: <RuntimeError>
Message: <"Error">
---Backtrace---
.+
---------------\Z}m) {
          assert_raise(ArgumentError, TypeError, "failed assert_raise") {
            raise "Error"
          }
        }
      end
      
      def test_assert_instance_of
        check_nothing_fails {
          assert_instance_of(String, "string")
        }
        check_nothing_fails {
          assert_instance_of(String, "string", "successful assert_instance_of")
        }
        check_nothing_fails {
          assert_instance_of(String, "string", "successful assert_instance_of")
        }
        check_fails(%Q{<"string"> expected to be an instance of\n<Hash> but was\n<String>.}) {
          assert_instance_of(Hash, "string")
        }
        check_fails(%Q{failed assert_instance_of.\n<"string"> expected to be an instance of\n<Hash> but was\n<String>.}) {
          assert_instance_of(Hash, "string", "failed assert_instance_of")
        }
      end
      
      def test_assert_nil
        check_nothing_fails {
          assert_nil(nil)
        }
        check_nothing_fails {
          assert_nil(nil, "successful assert_nil")
        }
        check_nothing_fails {
          assert_nil(nil, "successful assert_nil")
        }
        check_fails(%Q{<nil> expected but was\n<"string">.}) {
          assert_nil("string")
        }
        check_fails(%Q{failed assert_nil.\n<nil> expected but was\n<"string">.}) {
          assert_nil("string", "failed assert_nil")
        }
      end
      
      def test_assert_not_nil
        check_nothing_fails{assert_not_nil(false)}
        check_nothing_fails{assert_not_nil(false, "message")}
        check_fails("<nil> expected to not be nil."){assert_not_nil(nil)}
        check_fails("message.\n<nil> expected to not be nil.") {assert_not_nil(nil, "message")}
      end
        
      def test_assert_kind_of
        check_nothing_fails {
          assert_kind_of(Module, Array)
        }
        check_nothing_fails {
          assert_kind_of(Object, "string", "successful assert_kind_of")
        }
        check_nothing_fails {
          assert_kind_of(Object, "string", "successful assert_kind_of")
        }
        check_nothing_fails {
          assert_kind_of(Comparable, 1)
        }
        check_fails(%Q{<"string">\nexpected to be kind_of?\n<Class> but was\n<String>.}) {
          assert_kind_of(Class, "string")
        }
        check_fails(%Q{failed assert_kind_of.\n<"string">\nexpected to be kind_of?\n<Class> but was\n<String>.}) {
          assert_kind_of(Class, "string", "failed assert_kind_of")
        }
      end
      
      def test_assert_match
        check_nothing_fails {
          assert_match(/strin./, "string")
        }
        check_nothing_fails {
          assert_match("strin", "string")
        }
        check_nothing_fails {
          assert_match(/strin./, "string", "successful assert_match")
        }
        check_nothing_fails {
          assert_match(/strin./, "string", "successful assert_match")
        }
        check_fails(%Q{<"string"> expected to be =~\n</slin./>.}) {
          assert_match(/slin./, "string")
        }
        check_fails(%Q{<"string"> expected to be =~\n</strin\\./>.}) {
          assert_match("strin.", "string")
        }
        check_fails(%Q{failed assert_match.\n<"string"> expected to be =~\n</slin./>.}) {
          assert_match(/slin./, "string", "failed assert_match")
        }
      end
      
      def test_assert_same
        thing = "thing"
        check_nothing_fails {
          assert_same(thing, thing)
        }
        check_nothing_fails {
          assert_same(thing, thing, "successful assert_same")
        }
        check_nothing_fails {
          assert_same(thing, thing, "successful assert_same")
        }
        thing2 = "thing"
        check_fails(%Q{<"thing">\nwith id <#{thing.__id__}> expected to be equal? to\n<"thing">\nwith id <#{thing2.__id__}>.}) {
          assert_same(thing, thing2)
        }
        check_fails(%Q{failed assert_same.\n<"thing">\nwith id <#{thing.__id__}> expected to be equal? to\n<"thing">\nwith id <#{thing2.__id__}>.}) {
          assert_same(thing, thing2, "failed assert_same")
        }
      end
      
      def test_assert_nothing_raised
        check_nothing_fails {
          assert_nothing_raised {
            1 + 1
          }
        }
        check_nothing_fails {
          assert_nothing_raised("successful assert_nothing_raised") {
            1 + 1
          }
        }
        check_nothing_fails {
          assert_nothing_raised("successful assert_nothing_raised") {
            1 + 1
          }
        }
        check_nothing_fails {
          begin
            assert_nothing_raised(RuntimeError, StandardError, Comparable, "successful assert_nothing_raised") {
              raise ZeroDivisionError.new("ArgumentError")
            }
          rescue ZeroDivisionError
          end
        }
        check_fails("Should expect a class of exception, Object.\n<false> is not true.") {
          assert_nothing_raised(Object) {
            1 + 1
          }
        }
        check_fails(%r{\AException raised:\nClass: <RuntimeError>\nMessage: <"Error">\n---Backtrace---\n.+\n---------------\Z}m) {
          assert_nothing_raised {
            raise "Error"
          }
        }
        check_fails(%r{\Afailed assert_nothing_raised\.\nException raised:\nClass: <RuntimeError>\nMessage: <"Error">\n---Backtrace---\n.+\n---------------\Z}m) {
          assert_nothing_raised("failed assert_nothing_raised") {
            raise "Error"
          }
        }
        check_fails(%r{\AException raised:\nClass: <RuntimeError>\nMessage: <"Error">\n---Backtrace---\n.+\n---------------\Z}m) {
          assert_nothing_raised(StandardError, RuntimeError) {
            raise "Error"
          }
        }
        check_fails("Failure.") do
          assert_nothing_raised do
            flunk("Failure")
          end
        end
      end
      
      def test_flunk
        check_fails("Flunked.") {
          flunk
        }
        check_fails("flunk message.") {
          flunk("flunk message")
        }
      end
      
      def test_assert_not_same
        thing = "thing"
        thing2 = "thing"
        check_nothing_fails {
          assert_not_same(thing, thing2)
        }
        check_nothing_fails {
          assert_not_same(thing, thing2, "message")
        }
        check_fails(%Q{<"thing">\nwith id <#{thing.__id__}> expected to not be equal? to\n<"thing">\nwith id <#{thing.__id__}>.}) {
          assert_not_same(thing, thing)
        }
        check_fails(%Q{message.\n<"thing">\nwith id <#{thing.__id__}> expected to not be equal? to\n<"thing">\nwith id <#{thing.__id__}>.}) {
          assert_not_same(thing, thing, "message")
        }
      end
      
      def test_assert_not_equal
        check_nothing_fails {
          assert_not_equal("string1", "string2")
        }
        check_nothing_fails {
          assert_not_equal("string1", "string2", "message")
        }
        check_fails(%Q{<"string"> expected to be != to\n<"string">.}) {
          assert_not_equal("string", "string")
        }
        check_fails(%Q{message.\n<"string"> expected to be != to\n<"string">.}) {
          assert_not_equal("string", "string", "message")
        }
      end
      
      def test_assert_no_match
        check_nothing_fails{assert_no_match(/sling/, "string")}
        check_nothing_fails{assert_no_match(/sling/, "string", "message")}
        check_fails(%Q{The first argument to assert_no_match should be a Regexp.\n<"asdf"> expected to be an instance of\n<Regexp> but was\n<String>.}) do
          assert_no_match("asdf", "asdf")
        end
        check_fails(%Q{</string/> expected to not match\n<"string">.}) do
          assert_no_match(/string/, "string")
        end
        check_fails(%Q{message.\n</string/> expected to not match\n<"string">.}) do
          assert_no_match(/string/, "string", "message")
        end
      end
      
      def test_assert_throws
        check_nothing_fails {
          assert_throws(:thing, "message") {
            throw :thing
          }
        }
        check_fails("message.\n<:thing> expected to be thrown but\n<:thing2> was thrown.") {
          assert_throws(:thing, "message") {
            throw :thing2
          }
        }
        check_fails("message.\n<:thing> should have been thrown.") {
          assert_throws(:thing, "message") {
            1 + 1
          }
        }
      end
      
      def test_assert_nothing_thrown
        check_nothing_fails {
          assert_nothing_thrown("message") {
            1 + 1
          }
        }
        check_fails("message.\n<:thing> was thrown when nothing was expected.") {
          assert_nothing_thrown("message") {
            throw :thing
          }
        }
      end
      
      def test_assert_operator
        check_nothing_fails {
          assert_operator("thing", :==, "thing", "message")
        }
        check_fails(%Q{<0.15>\ngiven as the operator for #assert_operator must be a Symbol or #respond_to?(:to_str).}) do
          assert_operator("thing", 0.15, "thing")
        end
        check_fails(%Q{message.\n<"thing1"> expected to be\n==\n<"thing2">.}) {
          assert_operator("thing1", :==, "thing2", "message")
        }
      end
      
      def test_assert_respond_to
        check_nothing_fails {
          assert_respond_to("thing", :to_s, "message")
        }
        check_nothing_fails {
          assert_respond_to("thing", "to_s", "message")
        }
        check_fails("<0.15>\ngiven as the method name argument to #assert_respond_to must be a Symbol or #respond_to?(:to_str).") {
          assert_respond_to("thing", 0.15)
        }
        check_fails("message.\n<:symbol>\nof type <Symbol>\nexpected to respond_to?<:non_existent>.") {
          assert_respond_to(:symbol, :non_existent, "message")
        }
      end
      
      def test_assert_in_delta
        check_nothing_fails {
          assert_in_delta(1.4, 1.4, 0)
        }
        check_nothing_fails {
          assert_in_delta(0.5, 0.4, 0.1, "message")
        }
        check_nothing_fails {
          float_thing = Object.new
          def float_thing.to_f
            0.2
          end
          assert_in_delta(0.1, float_thing, 0.1)
        }
        check_fails("message.\n<0.5> and\n<0.4> expected to be within\n<0.05> of each other.") {
          assert_in_delta(0.5, 0.4, 0.05, "message")
        }
        check_fails(%r{The arguments must respond to to_f; the first float did not\.\n<.+>\nof type <Object>\nexpected to respond_to\?<:to_f>.}) {
          assert_in_delta(Object.new, 0.4, 0.1)
        }
        check_fails("The delta should not be negative.\n<-0.1> expected to be\n>=\n<0.0>.") {
          assert_in_delta(0.5, 0.4, -0.1, "message")
        }
      end
      
      def test_assert_send
        object = Object.new
        class << object
          private
          def return_argument(argument, bogus)
            return argument
          end
        end
        check_nothing_fails {
          assert_send([object, :return_argument, true, "bogus"], "message")
        }
        check_fails(%r{\Amessage\.\n<.+> expected to respond to\n<return_argument\(\[false, "bogus"\]\)> with a true value.\Z}) {
          assert_send([object, :return_argument, false, "bogus"], "message")
        }
      end
      
      def test_condition_invariant
        object = Object.new
        def object.inspect
          @changed = true
        end
        def object.==(other)
          @changed ||= false
          return (!@changed)
        end
        check_nothing_fails {
          assert_equal(object, object, "message")
        }
      end
  
      def add_failure(message, location=caller)
        if (!@catch_assertions)
          super
        end
      end
      
      def add_assertion
        if (!@catch_assertions)
          super
        else
          @actual_assertion_count += 1
        end
      end
    end
  end
end
