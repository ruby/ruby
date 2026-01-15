# frozen_string_literal: false
require 'test/unit'
require '-test-/postponed_job'

class TestPostponed_job < Test::Unit::TestCase
  def test_preregister_and_trigger
    assert_separately([], __FILE__, __LINE__, <<-'RUBY')
      require '-test-/postponed_job'
      Bug.postponed_job_preregister_and_call_without_sleep(counters = [])
      # i.e. rb_postponed_job_trigger performs coalescing
      assert_equal([3], counters)

      # i.e. rb_postponed_job_trigger resets after interrupts are checked
      Bug.postponed_job_preregister_and_call_with_sleep(counters = [])
      assert_equal([1, 2, 3], counters)
    RUBY
  end

  def test_multiple_preregistration
    assert_separately([], __FILE__, __LINE__, <<-'RUBY')
      require '-test-/postponed_job'
      handles = Bug.postponed_job_preregister_multiple_times
      # i.e. rb_postponed_job_preregister returns the same handle if preregistered multiple times
      assert_equal [handles[0]], handles.uniq
    RUBY
  end

  def test_multiple_preregistration_with_new_data
    assert_separately([], __FILE__, __LINE__, <<-'RUBY')
      require '-test-/postponed_job'
      values = Bug.postponed_job_preregister_calls_with_last_argument
      # i.e. the callback is called with the last argument it was preregistered with
      assert_equal [3, 4], values
    RUBY
  end

  def test_legacy_register
    assert_separately([], __FILE__, __LINE__, <<-'RUBY')
      require '-test-/postponed_job'
      direct, registered = [], []

      Bug.postponed_job_call_direct(direct)
      Bug.postponed_job_register(registered)

      assert_equal([0], direct)
      assert_equal([3], registered)

      Bug.postponed_job_register_one(ary = [])
      assert_equal [1], ary
    RUBY
  end

  def test_legacy_register_one_same
    assert_separately([], __FILE__, __LINE__, <<-'RUBY')
      require '-test-/postponed_job'
      # Registering the same job three times should result in three of the same handle
      handles = Bug.postponed_job_register_one_same
      assert_equal [handles[0]], handles.uniq
    RUBY
  end

  if Bug.respond_to?(:postponed_job_register_in_c_thread)
    def test_legacy_register_in_c_thread
      assert_separately([], __FILE__, __LINE__, <<-'RUBY')
        require '-test-/postponed_job'
        assert Bug.postponed_job_register_in_c_thread(ary = [])
        assert_equal [1], ary
      RUBY
    end
  end
end
