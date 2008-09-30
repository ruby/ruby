############################################################
# This file is imported from a different project.
# DO NOT make modifications in this repo.
# File a patch instead and assign it to Ryan Davis
############################################################

require 'stringio'
require 'mini/test'

Mini::Test.autorun

class Mini::Test
  attr_accessor :test_count
  attr_accessor :assertion_count
end

class TestMiniTest < Mini::Test::TestCase

  def setup
    srand 42
    Mini::Test::TestCase.reset
    @tu = Mini::Test.new
    @output = StringIO.new("")
    Mini::Test.output = @output
    assert_equal [0, 0], @tu.run_test_suites
  end

  def teardown
    Mini::Test.output = $stdout
    Object.send :remove_const, :ATestCase if defined? ATestCase
  end

  BT_MIDDLE = ["./lib/mini/test.rb:165:in `run_test_suites'",
               "./lib/mini/test.rb:161:in `each'",
               "./lib/mini/test.rb:161:in `run_test_suites'",
               "./lib/mini/test.rb:158:in `each'",
               "./lib/mini/test.rb:158:in `run_test_suites'",
               "./lib/mini/test.rb:139:in `run'",
               "./lib/mini/test.rb:106:in `run'"]

  def test_filter_backtrace
    # this is a semi-lame mix of relative paths.
    # I cheated by making the autotest parts not have ./
    bt = (["lib/autotest.rb:571:in `add_exception'",
           "test/test_autotest.rb:62:in `test_add_exception'",
           "./lib/mini/test.rb:165:in `__send__'"] +
          BT_MIDDLE +
          ["./lib/mini/test.rb:29",
           "test/test_autotest.rb:422"])
    ex = ["lib/autotest.rb:571:in `add_exception'",
          "test/test_autotest.rb:62:in `test_add_exception'"]
    fu = Mini::filter_backtrace(bt)

    assert_equal ex, fu
  end

  def test_filter_backtrace_all_unit
    bt = (["./lib/mini/test.rb:165:in `__send__'"] +
          BT_MIDDLE +
          ["./lib/mini/test.rb:29"])
    ex = bt.clone
    fu = Mini::filter_backtrace(bt)
    assert_equal ex, fu
  end

  def test_filter_backtrace_unit_starts
    bt = (["./lib/mini/test.rb:165:in `__send__'"] +
          BT_MIDDLE +
          ["./lib/mini/test.rb:29",
           "-e:1"])
    ex = ["-e:1"]
    fu = Mini::filter_backtrace(bt)
    assert_equal ex, fu
  end

  def test_class_puke_with_assertion_failed
    exception = Mini::Assertion.new "Oh no!"
    exception.set_backtrace ["unhappy"]
    assert_equal 'F', @tu.puke('SomeClass', 'method_name', exception)
    assert_equal 1, @tu.failures
    assert_match(/^Failure.*Oh no!/m, @tu.report.first)
  end

  def test_class_puke_with_failure_and_flunk_in_backtrace
    exception = begin
                  Mini::Test::TestCase.new('fake tc').flunk
                rescue Mini::Assertion => failure
                  failure
                end
    assert_equal 'F', @tu.puke('SomeClass', 'method_name', exception)
    refute @tu.report.any?{|line| line =~ /in .flunk/}
  end

  def test_class_puke_with_non_failure_exception
    exception = Exception.new("Oh no again!")
    assert_equal 'E', @tu.puke('SomeClass', 'method_name', exception)
    assert_equal 1, @tu.errors
    assert_match(/^Exception.*Oh no again!/m, @tu.report.first)
  end

  def test_class_run_test_suites
    tc = Class.new(Mini::Test::TestCase) do
      def test_something
        assert true
      end
    end

    Object.const_set(:ATestCase, tc)

    assert_equal [1, 1], @tu.run_test_suites
  end

  def test_run_failing # TODO: add error test
    tc = Class.new(Mini::Test::TestCase) do
      def test_something
        assert true
      end

      def test_failure
        assert false
      end
    end

    Object.const_set(:ATestCase, tc)

    @tu.run

    expected = "Loaded suite blah
Started
F.
Finished in 0.00

  1) Failure:
test_failure(ATestCase) [FILE:LINE]:
Failed assertion, no message given.

2 tests, 2 assertions, 1 failures, 0 errors, 0 skips
"
    util_assert_report expected
  end

  def test_run_error
    tc = Class.new(Mini::Test::TestCase) do
      def test_something
        assert true
      end

      def test_error
        raise "unhandled exception"
      end
    end

    Object.const_set(:ATestCase, tc)

    @tu.run

    expected = "Loaded suite blah
Started
E.
Finished in 0.00

  1) Error:
test_error(ATestCase):
RuntimeError: unhandled exception
    FILE:LINE:in `test_error'

2 tests, 1 assertions, 0 failures, 1 errors, 0 skips
"
    util_assert_report expected
  end

  def test_run_error_teardown
    tc = Class.new(Mini::Test::TestCase) do
      def test_something
        assert true
      end

      def teardown
        raise "unhandled exception"
      end
    end

    Object.const_set(:ATestCase, tc)

    @tu.run

    expected = "Loaded suite blah
Started
E
Finished in 0.00

  1) Error:
test_something(ATestCase):
RuntimeError: unhandled exception
    FILE:LINE:in `teardown'

1 tests, 1 assertions, 0 failures, 1 errors, 0 skips
"
    util_assert_report expected
  end

  def test_run_skip
    tc = Class.new(Mini::Test::TestCase) do
      def test_something
        assert true
      end

      def test_skip
        skip "not yet"
      end
    end

    Object.const_set(:ATestCase, tc)

    @tu.run

    expected = "Loaded suite blah
Started
S.
Finished in 0.00

  1) Skipped:
test_skip(ATestCase) [FILE:LINE]:
not yet

2 tests, 1 assertions, 0 failures, 0 errors, 1 skips
"
    util_assert_report expected
  end

  def util_assert_report expected = nil
    expected ||= "Loaded suite blah
Started
.
Finished in 0.00

1 tests, 1 assertions, 0 failures, 0 errors, 0 skips
"
    output = @output.string.sub(/Finished in .*/, "Finished in 0.00")
    output.sub!(/Loaded suite .*/, 'Loaded suite blah')
    output.sub!(/[\w\/\.]+:\d+/, 'FILE:LINE')
    assert_equal(expected, output)
  end

  def test_run_failing_filtered
    tc = Class.new(Mini::Test::TestCase) do
      def test_something
        assert true
      end

      def test_failure
        assert false
      end
    end

    Object.const_set(:ATestCase, tc)

    @tu.run(%w(-n /something/))

    util_assert_report
  end

  def test_run_passing
    tc = Class.new(Mini::Test::TestCase) do
      def test_something
        assert true
      end
    end

    Object.const_set(:ATestCase, tc)

    @tu.run

    util_assert_report
  end
end

class TestMiniTestTestCase < Mini::Test::TestCase
  def setup
    Mini::Test::TestCase.reset

    @tc = Mini::Test::TestCase.new 'fake tc'
    @zomg = "zomg ponies!"
    @assertion_count = 1
  end

  def teardown
    assert_equal(@assertion_count, @tc._assertions,
                 "expected #{@assertion_count} assertions to be fired during the test, not #{@tc._assertions}") if @tc._assertions
    Object.send :remove_const, :ATestCase if defined? ATestCase
  end

  def test_class_inherited
    @assertion_count = 0

    Object.const_set(:ATestCase, Class.new(Mini::Test::TestCase))

    assert_equal [ATestCase], Mini::Test::TestCase.test_suites
  end

  def test_class_test_suites
    @assertion_count = 0

    Object.const_set(:ATestCase, Class.new(Mini::Test::TestCase))

    assert_equal 1, Mini::Test::TestCase.test_suites.size
    assert_equal [ATestCase], Mini::Test::TestCase.test_suites
  end

  def test_class_asserts_match_refutes
    @assertion_count = 0

    methods = Mini::Assertions.public_instance_methods
    methods.map! { |m| m.to_s } if Symbol === methods.first

    ignores = %w(assert_block assert_no_match assert_not_equal assert_not_nil
                 assert_not_same assert_nothing_thrown assert_raise
                 assert_nothing_raised assert_raises assert_throws assert_send)
    asserts = methods.grep(/^assert/).sort - ignores
    refutes = methods.grep(/^refute/).sort - ignores

    assert_empty refutes.map { |n| n.sub(/^refute/, 'assert') } - asserts
    assert_empty asserts.map { |n| n.sub(/^assert/, 'refute') } - refutes
  end

  def test_assert
    @assertion_count = 2

    @tc.assert_equal true, @tc.assert(true), "returns true on success"
  end

  def test_assert__triggered
    util_assert_triggered "Failed assertion, no message given." do
      @tc.assert false
    end
  end

  def test_assert__triggered_message
    util_assert_triggered @zomg do
      @tc.assert false, @zomg
    end
  end

  def test_assert_block
    @tc.assert_block do
      true
    end
  end

  def test_assert_block_triggered
    util_assert_triggered 'Expected block to return true value.' do
      @tc.assert_block do
        false
      end
    end
  end

  def test_assert_empty
    @assertion_count = 2

    @tc.assert_empty []
  end

  def test_assert_empty_triggered
    @assertion_count = 2

    util_assert_triggered "Expected [1] to be empty." do
      @tc.assert_empty [1]
    end
  end

  def test_assert_equal
    @tc.assert_equal 1, 1
  end

  def test_assert_equal_different
    util_assert_triggered "Expected 1, not 2." do
      @tc.assert_equal 1, 2
    end
  end

  def test_assert_in_delta
    @tc.assert_in_delta 0.0, 1.0 / 1000, 0.1
  end

  def test_assert_in_delta_triggered
    util_assert_triggered 'Expected 0.0 - 0.001 (0.001) to be < 1.0e-06.' do
      @tc.assert_in_delta 0.0, 1.0 / 1000, 0.000001
    end
  end

  def test_assert_in_epsilon
    @assertion_count = 8

    @tc.assert_in_epsilon 10000, 9991
    @tc.assert_in_epsilon 9991, 10000
    @tc.assert_in_epsilon 1.0, 1.001
    @tc.assert_in_epsilon 1.001, 1.0

    @tc.assert_in_epsilon 10000, 9999.1, 0.0001
    @tc.assert_in_epsilon 9999.1, 10000, 0.0001
    @tc.assert_in_epsilon 1.0, 1.0001, 0.0001
    @tc.assert_in_epsilon 1.0001, 1.0, 0.0001
  end

  def test_assert_in_epsilon_triggered
    util_assert_triggered 'Expected 10000 - 9990 (10) to be < 9.99.' do
      @tc.assert_in_epsilon 10000, 9990
    end
  end

  def test_assert_includes
    @assertion_count = 2

    @tc.assert_includes [true], true
  end

  def test_assert_includes_triggered
    @assertion_count = 4

    e = @tc.assert_raises Mini::Assertion do
      @tc.assert_includes [true], false
    end

    expected = "Expected [true] to include false."
    assert_equal expected, e.message
  end

  def test_assert_instance_of
    @tc.assert_instance_of String, "blah"
  end

  def test_assert_instance_of_triggered
    util_assert_triggered 'Expected "blah" to be an instance of Array, not String.' do
      @tc.assert_instance_of Array, "blah"
    end
  end

  def test_assert_kind_of
    @tc.assert_kind_of String, "blah"
  end

  def test_assert_kind_of_triggered
    util_assert_triggered 'Expected "blah" to be a kind of Array, not String.' do
      @tc.assert_kind_of Array, "blah"
    end
  end

  def test_assert_match
    @assertion_count = 2
    @tc.assert_match "blah blah blah", /\w+/
  end

  def test_assert_match_triggered
    @assertion_count = 2
    util_assert_triggered 'Expected /\d+/ to match "blah blah blah".' do
      @tc.assert_match "blah blah blah", /\d+/
    end
  end

  def test_assert_nil
    @tc.assert_nil nil
  end

  def test_assert_nil_triggered
    util_assert_triggered 'Expected 42 to be nil.' do
      @tc.assert_nil 42
    end
  end

  def test_assert_operator
    @tc.assert_operator 2, :>, 1
  end

  def test_assert_operator_triggered
    util_assert_triggered "Expected 2 to be < 1." do
      @tc.assert_operator 2, :<, 1
    end
  end

  def test_assert_raises
    @assertion_count = 2

    @tc.assert_raises RuntimeError do
      raise "blah"
    end
  end

  def test_assert_raises_triggered_different
    @assertion_count = 2

    e = assert_raises Mini::Assertion do
      @tc.assert_raises RuntimeError do
        raise SyntaxError, "icky"
      end
    end

    expected = "<[RuntimeError]> exception expected, not
Class: <SyntaxError>
Message: <\"icky\">
---Backtrace---
FILE:LINE:in `test_assert_raises_triggered_different'
---------------.
Expected [RuntimeError] to include SyntaxError."

    assert_equal expected, expected.gsub(/[\w\/\.]+:\d+/, 'FILE:LINE')
  end

  def test_assert_raises_triggered_none
    e = assert_raises Mini::Assertion do
      @tc.assert_raises Mini::Assertion do
        # do nothing
      end
    end

    expected = "Mini::Assertion expected but nothing was raised."

    assert_equal expected, e.message
  end

  def test_assert_respond_to
    @tc.assert_respond_to "blah", :empty?
  end

  def test_assert_respond_to_triggered
    util_assert_triggered 'Expected "blah" (String) to respond to #rawr!.' do
      @tc.assert_respond_to "blah", :rawr!
    end
  end

  def test_assert_same
    @assertion_count = 3

    o = "blah"
    @tc.assert_same 1, 1
    @tc.assert_same :blah, :blah
    @tc.assert_same o, o
  end

  def test_assert_same_triggered
    @assertion_count = 2

    util_assert_triggered 'Expected 2 (0xXXX) to be the same as 1 (0xXXX).' do
      @tc.assert_same 1, 2
    end

    s1 = "blah"
    s2 = "blah"

    util_assert_triggered 'Expected "blah" (0xXXX) to be the same as "blah" (0xXXX).' do
      @tc.assert_same s1, s2
    end
  end

  def test_assert_send
    @tc.assert_send [1, :<, 2]
  end

  def test_assert_send_bad
    util_assert_triggered "Expected 1.>(*[2]) to return true." do
      @tc.assert_send [1, :>, 2]
    end
  end

  def test_assert_throws
    @tc.assert_throws(:blah) do
      throw :blah
    end
  end

  def test_assert_throws_different
    util_assert_triggered 'Expected :blah to have been thrown, not :not_blah.' do
      @tc.assert_throws(:blah) do
        throw :not_blah
      end
    end
  end

  def test_assert_throws_unthrown
    util_assert_triggered 'Expected :blah to have been thrown.' do
      @tc.assert_throws(:blah) do
        # do nothing
      end
    end
  end

  def test_capture_io
    @assertion_count = 0

    out, err = capture_io do
      puts 'hi'
      warn 'bye!'
    end

    assert_equal "hi\n", out
    assert_equal "bye!\n", err
  end

  def test_flunk
    util_assert_triggered 'Epic Fail!' do
      @tc.flunk
    end
  end

  def test_flunk_message
    util_assert_triggered @zomg do
      @tc.flunk @zomg
    end
  end

  def test_message
    @assertion_count = 0

    assert_equal "blah2.",         @tc.message { "blah2" }.call
    assert_equal "blah2.",         @tc.message("") { "blah2" }.call
    assert_equal "blah1.\nblah2.", @tc.message("blah1") { "blah2" }.call
  end

  def test_pass
    @tc.pass
  end

  def test_test_methods_sorted
    @assertion_count = 0

    sample_test_case = Class.new(Mini::Test::TestCase)

    class << sample_test_case
      def test_order; :sorted end
    end

    sample_test_case.instance_eval do
      define_method :test_test3 do assert "does not matter" end
      define_method :test_test2 do assert "does not matter" end
      define_method :test_test1 do assert "does not matter" end
    end

    expected = %w(test_test1 test_test2 test_test3)
    assert_equal expected, sample_test_case.test_methods
  end

  def test_test_methods_random
    @assertion_count = 0

    sample_test_case = Class.new(Mini::Test::TestCase)

    class << sample_test_case
      def test_order; :random end
    end

    sample_test_case.instance_eval do
      define_method :test_test1 do assert "does not matter" end
      define_method :test_test2 do assert "does not matter" end
      define_method :test_test3 do assert "does not matter" end
    end

    srand 42
    expected = %w(test_test1 test_test2 test_test3)
    max = expected.size
    expected = expected.sort_by { rand(max) }

    srand 42
    result = sample_test_case.test_methods

    assert_equal expected, result
  end

  def test_refute
    @assertion_count = 2

    @tc.assert_equal false, @tc.refute(false), "returns false on success"
  end

  def test_refute_empty
    @assertion_count = 2

    @tc.refute_empty [1]
  end

  def test_refute_empty_triggered
    @assertion_count = 2

    util_assert_triggered "Expected [] to not be empty." do
      @tc.refute_empty []
    end
  end

  def test_refute_equal
    @tc.refute_equal "blah", "yay"
  end

  def test_refute_equal_triggered
    util_assert_triggered 'Expected "blah" to not be equal to "blah".' do
      @tc.refute_equal "blah", "blah"
    end
  end

  def test_refute_in_delta
    @tc.refute_in_delta 0.0, 1.0 / 1000, 0.000001
  end

  def test_refute_in_delta_triggered
    util_assert_triggered 'Expected 0.0 - 0.001 (0.001) to not be < 0.1.' do
      @tc.refute_in_delta 0.0, 1.0 / 1000, 0.1
    end
  end

  def test_refute_in_epsilon
    @tc.refute_in_epsilon 10000, 9990
  end

  def test_refute_in_epsilon_triggered
    util_assert_triggered 'Expected 10000 - 9991 (9) to not be < 10.0.' do
      @tc.refute_in_epsilon 10000, 9991
      fail
    end
  end

  def test_refute_includes
    @assertion_count = 2

    @tc.refute_includes [true], false
  end

  def test_refute_includes_triggered
    @assertion_count = 4

    e = @tc.assert_raises Mini::Assertion do
      @tc.refute_includes [true], true
    end

    expected = "Expected [true] to not include true."
    assert_equal expected, e.message
  end

  def test_refute_instance_of
    @tc.refute_instance_of Array, "blah"
  end

  def test_refute_instance_of_triggered
    util_assert_triggered 'Expected "blah" to not be an instance of String.' do
      @tc.refute_instance_of String, "blah"
    end
  end

  def test_refute_kind_of
    @tc.refute_kind_of Array, "blah"
  end

  def test_refute_kind_of_triggered
    util_assert_triggered 'Expected "blah" to not be a kind of String.' do
      @tc.refute_kind_of String, "blah"
    end
  end

  def test_refute_match
    @tc.refute_match "blah blah blah", /\d+/
  end

  def test_refute_match_triggered
    util_assert_triggered 'Expected /\w+/ to not match "blah blah blah".' do
      @tc.refute_match "blah blah blah", /\w+/
    end
  end

  def test_refute_nil
    @tc.refute_nil 42
  end

  def test_refute_nil_triggered
    util_assert_triggered 'Expected nil to not be nil.' do
      @tc.refute_nil nil
    end
  end

  def test_refute_operator
    @tc.refute_operator 2, :<, 1
  end

  def test_refute_operator_triggered
    util_assert_triggered "Expected 2 to not be > 1." do
      @tc.refute_operator 2, :>, 1
    end
  end

  def test_refute_respond_to
    @tc.refute_respond_to "blah", :rawr!
  end

  def test_refute_respond_to_triggered
    util_assert_triggered 'Expected "blah" to not respond to empty?.' do
      @tc.refute_respond_to "blah", :empty?
    end
  end

  def test_refute_same
    @tc.refute_same 1, 2
  end

  # TODO: "with id <id>" crap from assertions.rb
  def test_refute_same_triggered
    util_assert_triggered 'Expected 1 to not be the same as 1.' do
      @tc.refute_same 1, 1
    end
  end

  def test_skip
    @assertion_count = 0

    util_assert_triggered "haha!", Mini::Skip do
      @tc.skip "haha!"
    end
  end

  def util_assert_triggered expected, klass = Mini::Assertion
    e = assert_raises(klass) do
      yield
    end

    msg = e.message.sub(/(---Backtrace---).*/m, '\1')
    msg.gsub!(/\(0x[0-9a-f]+\)/, '(0xXXX)')

    assert_equal expected, msg
  end

  if ENV['DEPRECATED'] then
    require 'test/unit/assertions'
    def test_assert_nothing_raised
      @tc.assert_nothing_raised do
        # do nothing
      end
    end

    def test_assert_nothing_raised_triggered
      expected = 'Exception raised:
Class: <RuntimeError>
Message: <"oops!">
---Backtrace---'

      util_assert_triggered expected do
        @tc.assert_nothing_raised do
          raise "oops!"
        end
      end
    end
  end
end
