######################################################################
# This file is imported from the minitest project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis.
######################################################################

require 'minitest/mock'
require 'minitest/unit'

MiniTest::Unit.autorun

class TestMiniTestMock < MiniTest::Unit::TestCase
  def setup
    @mock = MiniTest::Mock.new.expect(:foo, nil)
    @mock.expect(:meaning_of_life, 42)
  end

  def test_create_stub_method
    assert_nil @mock.foo
  end

  def test_allow_return_value_specification
    assert_equal 42, @mock.meaning_of_life
  end

  def test_blow_up_if_not_called
    @mock.foo

    util_verify_bad
  end

  def test_not_blow_up_if_everything_called
    @mock.foo
    @mock.meaning_of_life

    assert @mock.verify
  end

  def test_allow_expectations_to_be_added_after_creation
    @mock.expect(:bar, true)
    assert @mock.bar
  end

  def test_not_verify_if_new_expected_method_is_not_called
    @mock.foo
    @mock.meaning_of_life
    @mock.expect(:bar, true)

    util_verify_bad
  end

  def test_not_verify_if_unexpected_method_is_called
    assert_raises NoMethodError do
      @mock.unexpected
    end
  end

  def test_blow_up_on_wrong_number_of_arguments
    @mock.foo
    @mock.meaning_of_life
    @mock.expect(:sum, 3, [1, 2])

    assert_raises ArgumentError do
      @mock.sum
    end
  end

  def test_blow_up_on_wrong_arguments
    @mock.foo
    @mock.meaning_of_life
    @mock.expect(:sum, 3, [1, 2])

    @mock.sum(2, 4)

    util_verify_bad
  end

  def test_respond_appropriately
    assert @mock.respond_to?(:foo)
    assert !@mock.respond_to?(:bar)
  end

  def test_no_method_error_on_unexpected_methods
    assert_raises NoMethodError do
      @mock.bar
    end
  end

  def test_assign_per_mock_return_values
    a = MiniTest::Mock.new
    b = MiniTest::Mock.new

    a.expect(:foo, :a)
    b.expect(:foo, :b)

    assert_equal :a, a.foo
    assert_equal :b, b.foo
  end

  def test_do_not_create_stub_method_on_new_mocks
    a = MiniTest::Mock.new
    a.expect(:foo, :a)

    assert !MiniTest::Mock.new.respond_to?(:foo)
  end

  def util_verify_bad
    assert_raises MockExpectationError do
      @mock.verify
    end
  end
end
