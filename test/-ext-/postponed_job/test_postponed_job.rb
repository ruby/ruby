# frozen_string_literal: false
require 'test/unit'
require '-test-/postponed_job'

class TestPostponed_job < Test::Unit::TestCase
  def test_trigger_for_ractor
    omit 'Ractor not defined' unless defined?(Ractor)
    assert_separately([], __FILE__, __LINE__, <<-'RUBY')
      require '-test-/postponed_job'
      Warning[:experimental] = false

      executed_in = []
      Bug.postponed_job_preregister_for_ractor(executed_in)

      # trigger from a sub-Ractor, targeting the main Ractor
      r = Ractor.new(Ractor.current) do |main|
        Bug.postponed_job_trigger_for_ractor(main)
        :done
      end
      assert_equal :done, r.value

      # main picks the job up at one of its next interrupt checks
      50.times do
        break unless executed_in.empty?
        sleep 0.02
      end
      assert_equal [Ractor.current], executed_in
    RUBY
  end

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
end
