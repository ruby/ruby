require 'test/unit'

class TestTime < Test::Unit::TestCase
  def test_time_add()
    assert_equal(Time.utc(2000, 3, 21, 3, 30) + 3 * 3600,
                 Time.utc(2000, 3, 21, 6, 30))
    assert_equal(Time.utc(2000, 3, 21, 3, 30) + (-3 * 3600),
                 Time.utc(2000, 3, 21, 0, 30))
    assert_equal(0, (Time.at(1.1) + 0.9).usec)
  end

  def test_time_subt()
    assert_equal(Time.utc(2000, 3, 21, 3, 30) - 3 * 3600,
                 Time.utc(2000, 3, 21, 0, 30))
    assert_equal(Time.utc(2000, 3, 21, 3, 30) - (-3 * 3600),
                 Time.utc(2000, 3, 21, 6, 30))
    assert_equal(900000, (Time.at(1.1) - 0.2).usec)
  end

  def test_time_time()
    assert_equal(Time.utc(2000, 3, 21, 3, 30)  \
                -Time.utc(2000, 3, 21, 0, 30), 3*3600)
    assert_equal(Time.utc(2000, 3, 21, 0, 30)  \
                -Time.utc(2000, 3, 21, 3, 30), -3*3600)
  end

  def test_timegm_negative
    begin
      Time.at(-1)
    rescue ArgumentError
      return
    end
    assert_equal(-1, Time.utc(1969, 12, 31, 23, 59, 59).tv_sec)
    assert_equal(-2, Time.utc(1969, 12, 31, 23, 59, 58).tv_sec)
    assert_equal(-0x80000000, Time.utc(1901, 12, 13, 20, 45, 52).tv_sec)
  end
end
