require 'test/unit'
require 'rational'

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

  def negative_time_t?
    begin
      Time.at(-1)
      true
    rescue ArgumentError
      false
    end
  end

  def test_timegm
    if negative_time_t?
      assert_equal(-0x80000000, Time.utc(1901, 12, 13, 20, 45, 52).tv_sec)
      assert_equal(-2, Time.utc(1969, 12, 31, 23, 59, 58).tv_sec)
      assert_equal(-1, Time.utc(1969, 12, 31, 23, 59, 59).tv_sec)
    end

    assert_equal(0, Time.utc(1970, 1, 1, 0, 0, 0).tv_sec) # the Epoch
    assert_equal(1, Time.utc(1970, 1, 1, 0, 0, 1).tv_sec)
    assert_equal(31535999, Time.utc(1970, 12, 31, 23, 59, 59).tv_sec)
    assert_equal(31536000, Time.utc(1971, 1, 1, 0, 0, 0).tv_sec)
    assert_equal(78796799, Time.utc(1972, 6, 30, 23, 59, 59).tv_sec)

    # 1972-06-30T23:59:60Z is the first leap second.
    if Time.utc(1972, 7, 1, 0, 0, 0) - Time.utc(1972, 6, 30, 23, 59, 59) == 1
      # no leap second.
      assert_equal(78796800, Time.utc(1972, 7, 1, 0, 0, 0).tv_sec)
      assert_equal(78796801, Time.utc(1972, 7, 1, 0, 0, 1).tv_sec)
      assert_equal(946684800, Time.utc(2000, 1, 1, 0, 0, 0).tv_sec)
      assert_equal(0x7fffffff, Time.utc(2038, 1, 19, 3, 14, 7).tv_sec)
    else
      # leap seconds supported.
      assert_equal(2, Time.utc(1972, 7, 1, 0, 0, 0) - Time.utc(1972, 6, 30, 23, 59, 59))
      assert_equal(78796800, Time.utc(1972, 6, 30, 23, 59, 60).tv_sec)
      assert_equal(78796801, Time.utc(1972, 7, 1, 0, 0, 0).tv_sec)
      assert_equal(78796802, Time.utc(1972, 7, 1, 0, 0, 1).tv_sec)
      assert_equal(946684822, Time.utc(2000, 1, 1, 0, 0, 0).tv_sec)
    end
  end

  def test_huge_difference
    if negative_time_t?
      assert_equal(Time.at(-0x80000000), Time.at(0x7fffffff) - 0xffffffff, "[ruby-dev:22619]")
      assert_equal(Time.at(-0x80000000), Time.at(0x7fffffff) + (-0xffffffff))
      assert_equal(Time.at(0x7fffffff), Time.at(-0x80000000) + 0xffffffff, "[ruby-dev:22619]")
      assert_equal(Time.at(0x7fffffff), Time.at(-0x80000000) - (-0xffffffff))
    end
  end

  def test_big_minus
    begin
      bigtime0 = Time.at(2**60)
      bigtime1 = Time.at(2**60+1)
    rescue RangeError
      return
    end
    assert_equal(1.0, bigtime1 - bigtime0)
  end

  def test_at
    assert_equal(100000, Time.at(0.1).usec)
    assert_equal(10000, Time.at(0.01).usec)
    assert_equal(1000, Time.at(0.001).usec)
    assert_equal(100, Time.at(0.0001).usec)
    assert_equal(10, Time.at(0.00001).usec)
    assert_equal(1, Time.at(0.000001).usec)
    assert_equal(100000000, Time.at(0.1).nsec)
    assert_equal(10000000, Time.at(0.01).nsec)
    assert_equal(1000000, Time.at(0.001).nsec)
    assert_equal(100000, Time.at(0.0001).nsec)
    assert_equal(10000, Time.at(0.00001).nsec)
    assert_equal(1000, Time.at(0.000001).nsec)
    assert_equal(100, Time.at(0.0000001).nsec)
    assert_equal(10, Time.at(0.00000001).nsec)
    assert_equal(1, Time.at(0.000000001).nsec)
  end

  def test_at2
    assert_equal(100, Time.at(0, 0.1).nsec)
    assert_equal(10, Time.at(0, 0.01).nsec)
    assert_equal(1, Time.at(0, 0.001).nsec)
  end

  def test_at_rational
    assert_equal(1, Time.at(Rational(1,1) / 1000000000).nsec)
    assert_equal(1, Time.at(1167609600 + Rational(1,1) / 1000000000).nsec)
  end

  def test_utc_subsecond
    assert_equal(100000, Time.utc(2007,1,1,0,0,1.1).usec)
    assert_equal(100000, Time.utc(2007,1,1,0,0,Rational(11,10)).usec)
  end

  def test_eq_nsec
    assert_equal(Time.at(0, 0.123), Time.at(0, 0.123))
    assert_not_equal(Time.at(0, 0.123), Time.at(0, 0.124))
  end

  def assert_marshal_roundtrip(t)
    iv_names = t.instance_variables
    iv_vals1 = iv_names.map {|n| t.instance_variable_get n }
    m = Marshal.dump(t)
    t2 = Marshal.load(m)
    iv_vals2 = iv_names.map {|n| t2.instance_variable_get n }
    assert_equal(t, t2)
    assert_equal(iv_vals1, iv_vals2)
    t2
  end

  def test_marshal_nsec
    assert_marshal_roundtrip(Time.at(0, 0.123))
    assert_marshal_roundtrip(Time.at(0, 0.120))
  end

  def test_marshal_ivar
    t = Time.at(123456789, 987654.321)
    t.instance_eval { @var = 135 }
    assert_marshal_roundtrip(t)
    assert_marshal_roundtrip(Marshal.load(Marshal.dump(t)))
  end

end
