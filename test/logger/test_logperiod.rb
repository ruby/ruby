# coding: US-ASCII
# frozen_string_literal: false
require "logger"
require "time"

class TestLogPeriod < Test::Unit::TestCase
  def test_next_rotate_time
    time = Time.parse("2019-07-18 13:52:02")

    assert_next_rotate_time_words(time, "2019-07-19 00:00:00", ["daily", :daily])
    assert_next_rotate_time_words(time, "2019-07-21 00:00:00", ["weekly", :weekly])
    assert_next_rotate_time_words(time, "2019-08-01 00:00:00", ["monthly", :monthly])

    assert_raise(ArgumentError) { Logger::Period.next_rotate_time(time, "invalid") }
  end

  def test_next_rotate_time_extreme_cases
    # First day of Month and Saturday
    time = Time.parse("2018-07-01 00:00:00")

    assert_next_rotate_time_words(time, "2018-07-02 00:00:00", ["daily", :daily])
    assert_next_rotate_time_words(time, "2018-07-08 00:00:00", ["weekly", :weekly])
    assert_next_rotate_time_words(time, "2018-08-01 00:00:00", ["monthly", :monthly])

    assert_raise(ArgumentError) { Logger::Period.next_rotate_time(time, "invalid") }
  end

  def test_previous_period_end
    time = Time.parse("2019-07-18 13:52:02")

    assert_previous_period_end_words(time, "2019-07-17 23:59:59", ["daily", :daily])
    assert_previous_period_end_words(time, "2019-07-13 23:59:59", ["weekly", :weekly])
    assert_previous_period_end_words(time, "2019-06-30 23:59:59", ["monthly", :monthly])

    assert_raise(ArgumentError) { Logger::Period.previous_period_end(time, "invalid") }
  end

  def test_previous_period_end_extreme_cases
    # First day of Month and Saturday
    time = Time.parse("2018-07-01 00:00:00")
    previous_date = "2018-06-30 23:59:59"

    assert_previous_period_end_words(time, previous_date, ["daily", :daily])
    assert_previous_period_end_words(time, previous_date, ["weekly", :weekly])
    assert_previous_period_end_words(time, previous_date, ["monthly", :monthly])

    assert_raise(ArgumentError) { Logger::Period.previous_period_end(time, "invalid") }
  end

  private

  def assert_next_rotate_time_words(time, next_date, words)
    assert_time_words(:next_rotate_time, time, next_date, words)
  end

  def assert_previous_period_end_words(time, previous_date, words)
    assert_time_words(:previous_period_end, time, previous_date, words)
  end

  def assert_time_words(method, time, date, words)
    words.each do |word|
      daily_result = Logger::Period.public_send(method, time, word)
      expected_result = Time.parse(date)
      assert_equal(expected_result, daily_result)
    end
  end
end
