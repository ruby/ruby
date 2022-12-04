# frozen_string_literal: false
require 'test/unit'
require '-test-/postponed_job'

module Bug
  def self.postponed_job_call_direct_wrapper(*args)
    postponed_job_call_direct(*args)
  end

  def self.postponed_job_register_wrapper(*args)
    postponed_job_register(*args)
  end
end

class TestPostponed_job < Test::Unit::TestCase
  def test_register
    direct, registered = [], []

    Bug.postponed_job_call_direct_wrapper(direct)
    Bug.postponed_job_register_wrapper(registered)

    assert_equal([0], direct)
    assert_equal([3], registered)

    Bug.postponed_job_register_one(ary = [])
    assert_equal [1], ary
  end

  if Bug.respond_to?(:postponed_job_register_in_c_thread)
    def test_register_in_c_thread
      assert Bug.postponed_job_register_in_c_thread(ary = [])
      assert_equal [1], ary
    end
  end
end
