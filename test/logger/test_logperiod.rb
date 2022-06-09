# coding: US-ASCII
# frozen_string_literal: false
require 'logger'
require 'time'

class TestLogPeriod < Test::Unit::TestCase
  def test_next_rotate_time
    time = Time.parse("2019-07-18 13:52:02")

    daily_result = Logger::Period.next_rotate_time(time, 'daily')
    next_day = Time.parse("2019-07-19 00:00:00")
    assert_equal(next_day, daily_result)

    weekly_result = Logger::Period.next_rotate_time(time, 'weekly')
    next_week = Time.parse("2019-07-21 00:00:00")
    assert_equal(next_week, weekly_result)

    monthly_result = Logger::Period.next_rotate_time(time, 'monthly')
    next_month = Time.parse("2019-08-1 00:00:00")
    assert_equal(next_month, monthly_result)

    assert_raise(ArgumentError) { Logger::Period.next_rotate_time(time, 'invalid') }
  end

  def test_next_rotate_time_extreme_cases
    # First day of Month and Saturday
    time = Time.parse("2018-07-01 00:00:00")

    daily_result = Logger::Period.next_rotate_time(time, 'daily')
    next_day = Time.parse("2018-07-02 00:00:00")
    assert_equal(next_day, daily_result)

    weekly_result = Logger::Period.next_rotate_time(time, 'weekly')
    next_week = Time.parse("2018-07-08 00:00:00")
    assert_equal(next_week, weekly_result)

    monthly_result = Logger::Period.next_rotate_time(time, 'monthly')
    next_month = Time.parse("2018-08-1 00:00:00")
    assert_equal(next_month, monthly_result)

    assert_raise(ArgumentError) { Logger::Period.next_rotate_time(time, 'invalid') }
  end

  def test_previous_period_end
    time = Time.parse("2019-07-18 13:52:02")

    daily_result = Logger::Period.previous_period_end(time, 'daily')
    day_ago = Time.parse("2019-07-17 23:59:59")
    assert_equal(day_ago, daily_result)

    weekly_result = Logger::Period.previous_period_end(time, 'weekly')
    week_ago = Time.parse("2019-07-13 23:59:59")
    assert_equal(week_ago, weekly_result)

    monthly_result = Logger::Period.previous_period_end(time, 'monthly')
    month_ago = Time.parse("2019-06-30 23:59:59")
    assert_equal(month_ago, monthly_result)

    assert_raise(ArgumentError) { Logger::Period.next_rotate_time(time, 'invalid') }
  end

  def test_previous_period_end_extreme_cases
    # First day of Month and Saturday
    time = Time.parse("2018-07-01 00:00:00")

    daily_result = Logger::Period.previous_period_end(time, 'daily')
    day_ago = Time.parse("2018-06-30 23:59:59")
    assert_equal(day_ago, daily_result)

    weekly_result = Logger::Period.previous_period_end(time, 'weekly')
    week_ago = Time.parse("2018-06-30 23:59:59")
    assert_equal(week_ago, weekly_result)

    monthly_result = Logger::Period.previous_period_end(time, 'monthly')
    month_ago = Time.parse("2018-06-30 23:59:59")
    assert_equal(month_ago, monthly_result)

    assert_raise(ArgumentError) { Logger::Period.next_rotate_time(time, 'invalid') }
  end
end
