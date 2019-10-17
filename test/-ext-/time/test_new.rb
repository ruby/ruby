# frozen_string_literal: false
require 'test/unit'
require "-test-/time"

class  Bug::Time::Test_New < Test::Unit::TestCase
  def test_nano_new
    assert_equal(Time.at(1447087832, 476451.125), Bug::Time.nano_new(1447087832, 476451125))
    assert_not_equal(Time.at(1447087832, 476451.325), Bug::Time.nano_new(1447087832, 476451125))
    assert_equal(false, Bug::Time.nano_new(1447087832, 476451125).utc?)
  end

  def assert_time_equal(a, b, msg=nil)
    assert_equal(a, b, msg)
    assert_equal(a.gmtoff, b.gmtoff, msg)
    assert_equal(a.utc?, b.utc?, msg)
  end

  def test_timespec_new
    assert_time_equal(Time.at(1447087832, 476451.125).localtime(32400),
                 Bug::Time.timespec_new(1447087832, 476451125, 32400))
    assert_not_equal(Time.at(1447087832, 476451.128).localtime(32400),
                 Bug::Time.timespec_new(1447087832, 476451125, 32400))
    assert_equal(false, Bug::Time.timespec_new(1447087832, 476451125, 0).utc?)
    assert_equal(true,  Bug::Time.timespec_new(1447087832, 476451125, 0x7ffffffe).utc?)
    assert_equal(false, Bug::Time.timespec_new(1447087832, 476451125, 0x7fffffff).utc?)
    # Cannot compare Time.now.gmtoff with
    # Bug::Time.timespec_new(1447087832, 476451125, 0x7fffffff).gmtoff, because
    # it depends on whether the current time is in summer time (daylight-saving time) or not.
    t = Time.now
    assert_equal(t.gmtoff, Bug::Time.timespec_new(t.tv_sec, t.tv_nsec, 0x7fffffff).gmtoff)
    assert_time_equal(Time.at(1447087832, 476451.125).localtime(86399),
                 Bug::Time.timespec_new(1447087832, 476451125, 86399))
    assert_time_equal(Time.at(1447087832, 476451.125).localtime(-86399),
                 Bug::Time.timespec_new(1447087832, 476451125, -86399))
    assert_raise(ArgumentError){Bug::Time.timespec_new(1447087832, 476451125, 86400)}
    assert_raise(ArgumentError){Bug::Time.timespec_new(1447087832, 476451125,-86400)}
  end

  def test_timespec_now
    t0 = Time.now.to_r
    t = Bug::Time.timespec_now
    assert_in_delta 3, t0, t
  end
end
