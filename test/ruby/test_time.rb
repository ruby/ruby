# frozen_string_literal: false
require 'test/unit'
require 'delegate'
require 'timeout'
require 'delegate'

class TestTime < Test::Unit::TestCase
  def setup
    @verbose = $VERBOSE
  end

  def teardown
    $VERBOSE = @verbose
  end

  def in_timezone(zone)
    orig_zone = ENV['TZ']

    ENV['TZ'] = zone
    yield
  ensure
    ENV['TZ'] = orig_zone
  end

  def no_leap_seconds?
    # 1972-06-30T23:59:60Z is the first leap second.
    Time.utc(1972, 7, 1, 0, 0, 0) - Time.utc(1972, 6, 30, 23, 59, 59) == 1
  end

  def get_t2000
    if no_leap_seconds?
      # Sat Jan 01 00:00:00 UTC 2000
      Time.at(946684800).gmtime
    else
      Time.utc(2000, 1, 1)
    end
  end

  def test_new
    assert_equal(Time.new(2000,1,1,0,0,0), Time.new(2000))
    assert_equal(Time.new(2000,2,1,0,0,0), Time.new("2000", "Feb"))
    assert_equal(Time.utc(2000,2,10), Time.new(2000,2,10, 11,0,0, 3600*11))
    assert_equal(Time.utc(2000,2,10), Time.new(2000,2,9, 13,0,0, -3600*11))
    assert_equal(Time.utc(2000,2,29,23,0,0), Time.new(2000, 3, 1, 0, 0, 0, 3600))
    assert_equal(Time.utc(2000,2,10), Time.new(2000,2,10, 11,0,0, "+11:00"))
    assert_equal(Rational(1,2), Time.new(2000,2,10, 11,0,5.5, "+11:00").subsec)
    bug4090 = '[ruby-dev:42631]'
    tm = [2001,2,28,23,59,30]
    t = Time.new(*tm, "-12:00")
    assert_equal([2001,2,28,23,59,30,-43200], [t.year, t.month, t.mday, t.hour, t.min, t.sec, t.gmt_offset], bug4090)
    assert_raise(ArgumentError) { Time.new(2000,1,1, 0,0,0, "+01:60") }
    msg = /invalid value for Integer/
    assert_raise_with_message(ArgumentError, msg) { Time.new(2021, 1, 1, "+09:99") }
    assert_raise_with_message(ArgumentError, msg) { Time.new(2021, 1, "+09:99") }
    assert_raise_with_message(ArgumentError, msg) { Time.new(2021, "+09:99") }

    assert_equal([0, 0, 0, 1, 1, 2000, 6, 1, false, "UTC"], Time.new(2000, 1, 1, 0, 0, 0, "-00:00").to_a)
    assert_equal([0, 0, 0, 2, 1, 2000, 0, 2, false, "UTC"], Time.new(2000, 1, 1, 24, 0, 0, "-00:00").to_a)
  end

  def test_new_from_string
    assert_raise(ArgumentError) { Time.new(2021, 1, 1, "+09:99") }

    t = Time.utc(2020, 12, 24, 15, 56, 17)
    assert_equal(t, Time.new("2020-12-24T15:56:17Z"))
    assert_equal(t, Time.new("2020-12-25 00:56:17 +09:00"))
    assert_equal(t, Time.new("2020-12-25 00:57:47 +09:01:30"))
    assert_equal(t, Time.new("2020-12-25 00:56:17 +0900"))
    assert_equal(t, Time.new("2020-12-25 00:57:47 +090130"))
    assert_equal(t, Time.new("2020-12-25T00:56:17+09:00"))
    assert_raise_with_message(ArgumentError, /missing sec part/) {
      Time.new("2020-12-25 00:56 +09:00")
    }
    assert_raise_with_message(ArgumentError, /missing min part/) {
      Time.new("2020-12-25 00 +09:00")
    }

    assert_equal(Time.new(2021), Time.new("2021"))
    assert_equal(Time.new(2021, 12, 25, in: "+09:00"), Time.new("2021-12-25+09:00"))

    assert_equal(0.123456r, Time.new("2021-12-25 00:00:00.123456 +09:00").subsec)
    assert_equal(0.123456789r, Time.new("2021-12-25 00:00:00.123456789876 +09:00").subsec)
    assert_equal(0.123r, Time.new("2021-12-25 00:00:00.123456789876 +09:00", precision: 3).subsec)
    assert_equal(0.123456789876r, Time.new("2021-12-25 00:00:00.123456789876 +09:00", precision: nil).subsec)
    assert_raise_with_message(ArgumentError, "subsecond expected after dot: 00:56:17. ") {
      Time.new("2020-12-25 00:56:17. +0900")
    }
    assert_raise_with_message(ArgumentError, /year must be 4 or more/) {
      Time.new("021-12-25 00:00:00.123456 +09:00")
    }
    assert_raise_with_message(ArgumentError, /fraction min is.*56\./) {
      Time.new("2020-12-25 00:56. +0900")
    }
    assert_raise_with_message(ArgumentError, /fraction hour is.*00\./) {
      Time.new("2020-12-25 00. +0900")
    }
    assert_raise_with_message(ArgumentError, /two digits sec.*:017\b/) {
      Time.new("2020-12-25 00:56:017 +0900")
    }
    assert_raise_with_message(ArgumentError, /two digits sec.*:9\b/) {
      Time.new("2020-12-25 00:56:9 +0900")
    }
    assert_raise_with_message(ArgumentError, /sec out of range/) {
      Time.new("2020-12-25 00:56:64 +0900")
    }
    assert_raise_with_message(ArgumentError, /two digits min.*:056\b/) {
      Time.new("2020-12-25 00:056:17 +0900")
    }
    assert_raise_with_message(ArgumentError, /two digits min.*:5\b/) {
      Time.new("2020-12-25 00:5:17 +0900")
    }
    assert_raise_with_message(ArgumentError, /min out of range/) {
      Time.new("2020-12-25 00:64:17 +0900")
    }
    assert_raise_with_message(ArgumentError, /two digits hour.*\b000\b/) {
      Time.new("2020-12-25 000:56:17 +0900")
    }
    assert_raise_with_message(ArgumentError, /two digits hour.*\b0\b/) {
      Time.new("2020-12-25 0:56:17 +0900")
    }
    assert_raise_with_message(ArgumentError, /hour out of range/) {
      Time.new("2020-12-25 33:56:17 +0900")
    }
    assert_raise_with_message(ArgumentError, /two digits mday.*\b025\b/) {
      Time.new("2020-12-025 00:56:17 +0900")
    }
    assert_raise_with_message(ArgumentError, /two digits mday.*\b5\b/) {
      Time.new("2020-12-5 00:56:17 +0900")
    }
    assert_raise_with_message(ArgumentError, /mday out of range/) {
      Time.new("2020-12-33 00:56:17 +0900")
    }
    assert_raise_with_message(ArgumentError, /two digits mon.*\b012\b/) {
      Time.new("2020-012-25 00:56:17 +0900")
    }
    assert_raise_with_message(ArgumentError, /two digits mon.*\b1\b/) {
      Time.new("2020-1-25 00:56:17 +0900")
    }
    assert_raise_with_message(ArgumentError, /mon out of range/) {
      Time.new("2020-17-25 00:56:17 +0900")
    }
    assert_raise_with_message(ArgumentError, /no time information/) {
      Time.new("2020-12")
    }
    assert_raise_with_message(ArgumentError, /no time information/) {
      Time.new("2020-12-02")
    }
    assert_raise_with_message(ArgumentError, /can't parse/) {
      Time.new(" 2020-12-02 00:00:00")
    }
    assert_raise_with_message(ArgumentError, /can't parse/) {
      Time.new("2020-12-02 00:00:00 ")
    }
  end

  def test_time_add()
    assert_equal(Time.utc(2000, 3, 21, 3, 30) + 3 * 3600,
                 Time.utc(2000, 3, 21, 6, 30))
    assert_equal(Time.utc(2000, 3, 21, 3, 30) + (-3 * 3600),
                 Time.utc(2000, 3, 21, 0, 30))
    assert_equal(0, (Time.at(1.1) + 0.9).usec)

    assert_predicate((Time.utc(2000, 4, 1) + 24), :utc?)
    assert_not_predicate((Time.local(2000, 4, 1) + 24), :utc?)

    t = Time.new(2000, 4, 1, 0, 0, 0, "+01:00") + 24
    assert_not_predicate(t, :utc?)
    assert_equal(3600, t.utc_offset)
    t = Time.new(2000, 4, 1, 0, 0, 0, "+02:00") + 24
    assert_not_predicate(t, :utc?)
    assert_equal(7200, t.utc_offset)
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

    if no_leap_seconds?
      assert_equal(78796800, Time.utc(1972, 7, 1, 0, 0, 0).tv_sec)
      assert_equal(78796801, Time.utc(1972, 7, 1, 0, 0, 1).tv_sec)
      assert_equal(946684800, Time.utc(2000, 1, 1, 0, 0, 0).tv_sec)

      # Giveup to try 2nd test because some state is changed.
      omit if Test::Unit::Runner.current_repeat_count > 0

      assert_equal(0x7fffffff, Time.utc(2038, 1, 19, 3, 14, 7).tv_sec)
      assert_equal(0x80000000, Time.utc(2038, 1, 19, 3, 14, 8).tv_sec)
    else
      assert_equal(2, Time.utc(1972, 7, 1, 0, 0, 0) - Time.utc(1972, 6, 30, 23, 59, 59))
      assert_equal(78796800, Time.utc(1972, 6, 30, 23, 59, 60).tv_sec)
      assert_equal(78796801, Time.utc(1972, 7, 1, 0, 0, 0).tv_sec)
      assert_equal(78796802, Time.utc(1972, 7, 1, 0, 0, 1).tv_sec)
      assert_equal(946684822, Time.utc(2000, 1, 1, 0, 0, 0).tv_sec)
    end
  end

  def test_strtime
    t = nil
    assert_nothing_raised { t = Time.utc("2000", "1", "2" , "3", "4", "5") }
    assert_equal(Time.utc(2000,1,2,3,4,5), t)
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
    assert_equal(100000, Time.at("0.1".to_r).usec)
    assert_equal(10000, Time.at("0.01".to_r).usec)
    assert_equal(1000, Time.at("0.001".to_r).usec)
    assert_equal(100, Time.at("0.0001".to_r).usec)
    assert_equal(10, Time.at("0.00001".to_r).usec)
    assert_equal(1, Time.at("0.000001".to_r).usec)
    assert_equal(100000000, Time.at("0.1".to_r).nsec)
    assert_equal(10000000, Time.at("0.01".to_r).nsec)
    assert_equal(1000000, Time.at("0.001".to_r).nsec)
    assert_equal(100000, Time.at("0.0001".to_r).nsec)
    assert_equal(10000, Time.at("0.00001".to_r).nsec)
    assert_equal(1000, Time.at("0.000001".to_r).nsec)
    assert_equal(100, Time.at("0.0000001".to_r).nsec)
    assert_equal(10, Time.at("0.00000001".to_r).nsec)
    assert_equal(1, Time.at("0.000000001".to_r).nsec)
    assert_equal(100000, Time.at(0.1).usec)
    assert_equal(10000, Time.at(0.01).usec)
    assert_equal(1000, Time.at(0.001).usec)
    assert_equal(100, Time.at(0.0001).usec)
    assert_equal(10, Time.at(0.00001).usec)
    assert_equal(3, Time.at(0.000003).usec)
    assert_equal(100000000, Time.at(0.1).nsec)
    assert_equal(10000000, Time.at(0.01).nsec)
    assert_equal(1000000, Time.at(0.001).nsec)
    assert_equal(100000, Time.at(0.0001).nsec)
    assert_equal(10000, Time.at(0.00001).nsec)
    assert_equal(3000, Time.at(0.000003).nsec)
    assert_equal(200, Time.at(0.0000002r).nsec)
    assert_in_delta(200, Time.at(0.0000002).nsec, 1, "should be within FP error")
    assert_equal(10, Time.at(0.00000001).nsec)
    assert_equal(1, Time.at(0.000000001).nsec)

    assert_equal(0, Time.at(1e-10).nsec)
    assert_equal(0, Time.at(4e-10).nsec)
    assert_equal(0, Time.at(6e-10).nsec)
    assert_equal(1, Time.at(14e-10).nsec)
    assert_equal(1, Time.at(16e-10).nsec)
    if negative_time_t?
      assert_equal(999999999, Time.at(-1e-10).nsec)
      assert_equal(999999999, Time.at(-4e-10).nsec)
      assert_equal(999999999, Time.at(-6e-10).nsec)
      assert_equal(999999998, Time.at(-14e-10).nsec)
      assert_equal(999999998, Time.at(-16e-10).nsec)
    end

    t = Time.at(-4611686019).utc
    assert_equal(1823, t.year)

    t = Time.at(4611686018, 999999).utc
    assert_equal(2116, t.year)
    assert_equal("0.999999".to_r, t.subsec)

    t = Time.at(2**40 + "1/3".to_r, 9999999999999).utc
    assert_equal(36812, t.year)

    t = Time.at(-0x3fff_ffff_ffff_ffff)
    assert_equal(-146138510344, t.year)
    t = Time.at(-0x4000_0000_0000_0000)
    assert_equal(-146138510344, t.year)
    t = Time.at(-0x4000_0000_0000_0001)
    assert_equal(-146138510344, t.year)
    t = Time.at(-0x5000_0000_0000_0001)
    assert_equal(-182673138422, t.year)
    t = Time.at(-0x6000_0000_0000_0000)
    assert_equal(-219207766501, t.year)

    t = Time.at(0).utc
    assert_equal([1970,1,1, 0,0,0], [t.year, t.mon, t.day, t.hour, t.min, t.sec])
    t = Time.at(-86400).utc
    assert_equal([1969,12,31, 0,0,0], [t.year, t.mon, t.day, t.hour, t.min, t.sec])
    t = Time.at(-86400 * (400 * 365 + 97)).utc
    assert_equal([1970-400,1,1, 0,0,0], [t.year, t.mon, t.day, t.hour, t.min, t.sec])
    t = Time.at(-86400 * (400 * 365 + 97)*1000).utc
    assert_equal([1970-400*1000,1,1, 0,0,0], [t.year, t.mon, t.day, t.hour, t.min, t.sec])
    t = Time.at(-86400 * (400 * 365 + 97)*2421).utc
    assert_equal([1970-400*2421,1,1, 0,0,0], [t.year, t.mon, t.day, t.hour, t.min, t.sec])
    t = Time.at(-86400 * (400 * 365 + 97)*1000000).utc
    assert_equal([1970-400*1000000,1,1, 0,0,0], [t.year, t.mon, t.day, t.hour, t.min, t.sec])

    t = Time.at(-30613683110400).utc
    assert_equal([-968139,1,1, 0,0,0], [t.year, t.mon, t.day, t.hour, t.min, t.sec])
    t = Time.at(-30613683110401).utc
    assert_equal([-968140,12,31, 23,59,59], [t.year, t.mon, t.day, t.hour, t.min, t.sec])
  end

  def test_at2
    assert_equal(100, Time.at(0, 0.1).nsec)
    assert_equal(10, Time.at(0, 0.01).nsec)
    assert_equal(1, Time.at(0, 0.001).nsec)
  end

  def test_at_splat
    assert_equal(Time.at(1, 2), Time.at(*[1, 2]))
  end

  def test_at_with_unit
    assert_equal(123456789, Time.at(0, 123456789, :nanosecond).nsec)
    assert_equal(123456789, Time.at(0, 123456789, :nsec).nsec)
    assert_equal(123456000, Time.at(0, 123456, :microsecond).nsec)
    assert_equal(123456000, Time.at(0, 123456, :usec).nsec)
    assert_equal(123000000, Time.at(0, 123, :millisecond).nsec)
    assert_raise(ArgumentError){ Time.at(0, 1, 2) }
    assert_raise(ArgumentError){ Time.at(0, 1, :invalid) }
    assert_raise(ArgumentError){ Time.at(0, 1, nil) }
  end

  def test_at_rational
    assert_equal(1, Time.at(Rational(1,1) / 1000000000).nsec)
    assert_equal(1, Time.at(1167609600 + Rational(1,1) / 1000000000).nsec)
  end

  def test_utc_subsecond
    assert_equal(500000, Time.utc(2007,1,1,0,0,1.5).usec)
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

  def test_marshal_nsec_191
    # generated by ruby 1.9.1p376
    m = "\x04\bIu:\tTime\r \x80\x11\x80@\xE2\x01\x00\x06:\rsubmicro\"\ax\x90"
    t = Marshal.load(m)
    assert_equal(Time.at(Rational(123456789, 1000000000)), t, "[ruby-dev:40133]")
  end

  def test_marshal_rational
    assert_marshal_roundtrip(Time.at(0, Rational(1,3)))
    assert_not_match(/Rational/, Marshal.dump(Time.at(0, Rational(1,3))))
  end

  def test_marshal_ivar
    t = Time.at(123456789, 987654.321)
    t.instance_eval { @var = 135 }
    assert_marshal_roundtrip(t)
    assert_marshal_roundtrip(Marshal.load(Marshal.dump(t)))
  end

  def test_marshal_timezone
    bug = '[ruby-dev:40063]'

    t1 = Time.gm(2000)
    m = Marshal.dump(t1.getlocal("-02:00"))
    t2 = Marshal.load(m)
    assert_equal(t1, t2)
    assert_equal(-7200, t2.utc_offset, bug)
    m = Marshal.dump(t1.getlocal("+08:15"))
    t2 = Marshal.load(m)
    assert_equal(t1, t2)
    assert_equal(29700, t2.utc_offset, bug)
  end

  def test_marshal_zone
    t = Time.utc(2013, 2, 24)
    assert_equal('UTC', t.zone)
    assert_equal('UTC', Marshal.load(Marshal.dump(t)).zone)

    in_timezone('JST-9') do
      t = Time.local(2013, 2, 24)
      assert_equal('JST', Time.local(2013, 2, 24).zone)
      t = Marshal.load(Marshal.dump(t))
      assert_equal('JST', t.zone)
      assert_equal('JST', (t+1).zone, '[ruby-core:81892] [Bug #13710]')
    end
  end

  def test_marshal_zone_gc
    assert_separately(%w(--disable-gems), <<-'end;', timeout: 30)
      ENV["TZ"] = "JST-9"
      s = Marshal.dump(Time.now)
      t = Marshal.load(s)
      n = 0
      done = 100000
      while t.zone.dup == "JST" && n < done
        n += 1
      end
      assert_equal done, n, "Bug #9652"
      assert_equal "JST", t.zone, "Bug #9652"
    end;
  end

  def test_marshal_to_s
    t1 = Time.new(2011,11,8, 0,42,25, 9*3600)
    t2 = Time.at(Marshal.load(Marshal.dump(t1)))
    assert_equal("2011-11-08 00:42:25 +0900", t2.to_s,
      "[ruby-dev:44827] [Bug #5586]")
  end

  Bug8795 = '[ruby-core:56648] [Bug #8795]'

  def test_marshal_broken_offset
    data = "\x04\bIu:\tTime\r\xEFF\x1C\x80\x00\x00\x00\x00\x06:\voffset"
    t1 = t2 = nil
    in_timezone('UTC') do
      assert_nothing_raised(TypeError, ArgumentError, Bug8795) do
        t1 = Marshal.load(data + "T")
        t2 = Marshal.load(data + "\"\x0ebadoffset")
      end
      assert_equal(0, t1.utc_offset)
      assert_equal(0, t2.utc_offset)
    end
  end

  def test_marshal_broken_zone
    data = "\x04\bIu:\tTime\r\xEFF\x1C\x80\x00\x00\x00\x00\x06:\tzone"
    t1 = t2 = nil
    in_timezone('UTC') do
      assert_nothing_raised(TypeError, ArgumentError, Bug8795) do
        t1 = Marshal.load(data + "T")
        t2 = Marshal.load(data + "\"\b\0\0\0")
      end
      assert_equal('UTC', t1.zone)
      assert_equal('UTC', t2.zone)
    end
  end

  def test_marshal_broken_month
    data = "\x04\x08u:\tTime\r\x20\x7c\x1e\xc0\x00\x00\x00\x00"
    assert_equal(Time.utc(2022, 4, 1), Marshal.load(data))
  end

  def test_marshal_distant_past
    assert_marshal_roundtrip(Time.utc(1890, 1, 1))
    assert_marshal_roundtrip(Time.utc(-4.5e9, 1, 1))
  end

  def test_marshal_distant_future
    assert_marshal_roundtrip(Time.utc(30000, 1, 1))
    assert_marshal_roundtrip(Time.utc(5.67e9, 4, 8))
  end

  def test_at3
    t2000 = get_t2000
    assert_equal(t2000, Time.at(t2000))
#    assert_raise(RangeError) do
#      Time.at(2**31-1, 1_000_000)
#      Time.at(2**63-1, 1_000_000)
#    end
#    assert_raise(RangeError) do
#      Time.at(-2**31, -1_000_000)
#      Time.at(-2**63, -1_000_000)
#    end
  end

  def test_utc_or_local
    t2000 = get_t2000
    assert_equal(t2000, Time.gm(2000))
    assert_equal(t2000, Time.gm(0, 0, 0, 1, 1, 2000, :foo, :bar, false, :baz))
    assert_equal(t2000, Time.gm(2000, "jan"))
    assert_equal(t2000, Time.gm(2000, "1"))
    assert_equal(t2000, Time.gm(2000, 1, 1, 0, 0, 0, 0))
    assert_equal(t2000, Time.gm(2000, 1, 1, 0, 0, 0, "0"))
    assert_equal(t2000, Time.gm(2000, 1, 1, 0, 0, "0", :foo, :foo))
    assert_raise(ArgumentError) { Time.gm(2000, 1, 1, 0, 0, -1, :foo, :foo) }
    assert_raise(ArgumentError) { Time.gm(2000, 1, 1, 0, 0, -1.0, :foo, :foo) }
    assert_raise(RangeError) do
      Time.gm(2000, 1, 1, 0, 0, 10_000_000_000_000_000_001.0, :foo, :foo)
    end
    assert_raise(ArgumentError) { Time.gm(2000, 1, 1, 0, 0, -(2**31), :foo, :foo) }
    o = Object.new
    def o.to_int; 0; end
    def o.to_r; nil; end
    assert_raise(TypeError) { Time.gm(2000, 1, 1, 0, 0, o, :foo, :foo) }
    class << o; remove_method(:to_r); end
    def o.to_r; ""; end
    assert_raise(TypeError) { Time.gm(2000, 1, 1, 0, 0, o, :foo, :foo) }
    class << o; remove_method(:to_r); end
    def o.to_r; Rational(11); end
    assert_equal(11, Time.gm(2000, 1, 1, 0, 0, o).sec)
    o = Object.new
    def o.to_int; 10; end
    assert_equal(10, Time.gm(2000, 1, 1, 0, 0, o).sec)
    assert_raise(ArgumentError) { Time.gm(2000, 13) }

    t = Time.local(2000)
    assert_equal(t.gmt_offset, t2000 - t)

    assert_equal(-4427700000, Time.utc(-4427700000,12,1).year)
    assert_equal(-2**30+10, Time.utc(-2**30+10,1,1).year)

    assert_raise(ArgumentError) { Time.gm(2000, 1, -1) }
    assert_raise(ArgumentError) { Time.gm(2000, 1, 2**30 + 1) }
    assert_raise(ArgumentError) { Time.gm(2000, 1, -2**30 + 1) }
  end

  def test_time_interval
    m = Thread::Mutex.new.lock
    assert_nothing_raised {
      Timeout.timeout(10) {
        m.sleep(0)
      }
    }
    assert_raise(ArgumentError) { m.sleep(-1) }
    assert_raise(TypeError) { m.sleep("") }
    assert_raise(TypeError) { sleep("") }
    obj = eval("class C\u{1f5ff}; self; end").new
    assert_raise_with_message(TypeError, /C\u{1f5ff}/) {m.sleep(obj)}
    assert_raise_with_message(TypeError, /C\u{1f5ff}/) {sleep(obj)}
  end

  def test_to_f
    t2000 = Time.at(946684800).gmtime
    assert_equal(946684800.0, t2000.to_f)
  end

  def test_to_f_accuracy
    # https://bugs.ruby-lang.org/issues/10135#note-1
    f = 1381089302.195
    assert_equal(f, Time.at(f).to_f, "[ruby-core:64373] [Bug #10135] note-1")
  end

  def test_cmp
    t2000 = get_t2000
    assert_equal(-1, t2000 <=> Time.gm(2001))
    assert_equal(1, t2000 <=> Time.gm(1999))
    assert_nil(t2000 <=> 0)
  end

  def test_eql
    t2000 = get_t2000
    assert_operator(t2000, :eql?, t2000)
    assert_not_operator(t2000, :eql?, Time.gm(2001))
  end

  def test_utc_p
    assert_predicate(Time.gm(2000), :gmt?)
    assert_not_predicate(Time.local(2000), :gmt?)
    assert_not_predicate(Time.at(0), :gmt?)
  end

  def test_hash
    t2000 = get_t2000
    assert_kind_of(Integer, t2000.hash)
  end

  def test_reinitialize
    bug8099 = '[ruby-core:53436] [Bug #8099]'
    t2000 = get_t2000
    assert_raise(TypeError, bug8099) {
      t2000.send(:initialize, 2013, 03, 14)
    }
    assert_equal(get_t2000, t2000, bug8099)
  end

  def test_init_copy
    t2000 = get_t2000
    assert_equal(t2000, t2000.dup)
    assert_raise(TypeError) do
      t2000.instance_eval { initialize_copy(nil) }
    end
  end

  def test_localtime_gmtime
    assert_nothing_raised do
      t = Time.gm(2000)
      assert_predicate(t, :gmt?)
      t.localtime
      assert_not_predicate(t, :gmt?)
      t.localtime
      assert_not_predicate(t, :gmt?)
      t.gmtime
      assert_predicate(t, :gmt?)
      t.gmtime
      assert_predicate(t, :gmt?)
    end

    t1 = Time.gm(2000)
    t2 = t1.getlocal
    assert_equal(t1, t2)
    t3 = t1.getlocal("-02:00")
    assert_equal(t1, t3)
    assert_equal(-7200, t3.utc_offset)
    assert_equal([1999, 12, 31, 22, 0, 0], [t3.year, t3.mon, t3.mday, t3.hour, t3.min, t3.sec])
    t1.localtime
    assert_equal(t1, t2)
    assert_equal(t1.gmt?, t2.gmt?)
    assert_equal(t1, t3)

    t1 = Time.local(2000)
    t2 = t1.getgm
    assert_equal(t1, t2)
    t3 = t1.getlocal("-02:00")
    assert_equal(t1, t3)
    assert_equal(-7200, t3.utc_offset)
    t1.gmtime
    assert_equal(t1, t2)
    assert_equal(t1.gmt?, t2.gmt?)
    assert_equal(t1, t3)
  end

  def test_asctime
    t2000 = get_t2000
    assert_equal("Sat Jan  1 00:00:00 2000", t2000.asctime)
    assert_equal(Encoding::US_ASCII, t2000.asctime.encoding)
    assert_kind_of(String, Time.at(0).asctime)
  end

  def test_to_s
    t2000 = get_t2000
    assert_equal("2000-01-01 00:00:00 UTC", t2000.to_s)
    assert_equal(Encoding::US_ASCII, t2000.to_s.encoding)
    assert_kind_of(String, Time.at(946684800).getlocal.to_s)
    assert_equal(Time.at(946684800).getlocal.to_s, Time.at(946684800).to_s)
  end

  def test_inspect
    t2000 = get_t2000
    assert_equal("2000-01-01 00:00:00 UTC", t2000.inspect)
    assert_equal(Encoding::US_ASCII, t2000.inspect.encoding)
    assert_kind_of(String, Time.at(946684800).getlocal.inspect)
    assert_equal(Time.at(946684800).getlocal.inspect, Time.at(946684800).inspect)

    t2000 = get_t2000 + 1/10r
    assert_equal("2000-01-01 00:00:00.1 UTC", t2000.inspect)
    t2000 = get_t2000 + 1/1000000000r
    assert_equal("2000-01-01 00:00:00.000000001 UTC", t2000.inspect)
    t2000 = get_t2000 + 1/10000000000r
    assert_equal("2000-01-01 00:00:00 1/10000000000 UTC", t2000.inspect)
    t2000 = get_t2000 + 0.1
    assert_equal("2000-01-01 00:00:00 3602879701896397/36028797018963968 UTC", t2000.inspect)

    t2000 = get_t2000
    t2000 = t2000.localtime(9*3600)
    assert_equal("2000-01-01 09:00:00 +0900", t2000.inspect)

    t2000 = get_t2000.localtime(9*3600) + 1/10r
    assert_equal("2000-01-01 09:00:00.1 +0900", t2000.inspect)

    t2000 = get_t2000
    assert_equal("2000-01-01 09:12:00 +0912", t2000.localtime(9*3600+12*60).inspect)
    assert_equal("2000-01-01 09:12:34 +091234", t2000.localtime(9*3600+12*60+34).inspect)
  end

  def assert_zone_encoding(time)
    zone = time.zone
    assert_predicate(zone, :valid_encoding?)
    if zone.ascii_only?
      assert_equal(Encoding::US_ASCII, zone.encoding)
    else
      enc = Encoding.default_internal || Encoding.find('locale')
      assert_equal(enc, zone.encoding)
    end
  end

  def test_zone
    assert_zone_encoding Time.now
    t = Time.now.utc
    assert_equal("UTC", t.zone)
    assert_nil(t.getlocal(0).zone)
    assert_nil(t.getlocal("+02:00").zone)
  end

  def test_plus_minus
    t2000 = get_t2000
    # assert_raise(RangeError) { t2000 + 10000000000 }
    # assert_raise(RangeError)  t2000 - 3094168449 }
    # assert_raise(RangeError) { t2000 + 1200798848 }
    assert_raise(TypeError) { t2000 + Time.now }
  end

  def test_plus_type
    t0 = Time.utc(2000,1,1)
    n0 = t0.to_i
    n1 = n0+1
    t1 = Time.at(n1)
    assert_equal(t1, t0 + 1)
    assert_equal(t1, t0 + 1.0)
    assert_equal(t1, t0 + Rational(1,1))
    assert_equal(t1, t0 + SimpleDelegator.new(1))
    assert_equal(t1, t0 + SimpleDelegator.new(1.0))
    assert_equal(t1, t0 + SimpleDelegator.new(Rational(1,1)))
    assert_raise(TypeError) { t0 + nil }
    assert_raise(TypeError) { t0 + "1" }
    assert_raise(TypeError) { t0 + SimpleDelegator.new("1") }
    assert_equal(0.5, (t0 + 1.5).subsec)
    assert_equal(Rational(1,3), (t0 + Rational(4,3)).subsec)
    assert_equal(0.5, (t0 + SimpleDelegator.new(1.5)).subsec)
    assert_equal(Rational(1,3), (t0 + SimpleDelegator.new(Rational(4,3))).subsec)
  end

  def test_minus
    t = Time.at(-4611686018).utc - 100
    assert_equal(1823, t.year)
  end

  def test_readers
    t2000 = get_t2000
    assert_equal(0, t2000.sec)
    assert_equal(0, t2000.min)
    assert_equal(0, t2000.hour)
    assert_equal(1, t2000.mday)
    assert_equal(1, t2000.mon)
    assert_equal(2000, t2000.year)
    assert_equal(6, t2000.wday)
    assert_equal(1, t2000.yday)
    assert_equal(false, t2000.isdst)
    assert_equal("UTC", t2000.zone)
    assert_zone_encoding(t2000)
    assert_equal(0, t2000.gmt_offset)
    assert_not_predicate(t2000, :sunday?)
    assert_not_predicate(t2000, :monday?)
    assert_not_predicate(t2000, :tuesday?)
    assert_not_predicate(t2000, :wednesday?)
    assert_not_predicate(t2000, :thursday?)
    assert_not_predicate(t2000, :friday?)
    assert_predicate(t2000, :saturday?)
    assert_equal([0, 0, 0, 1, 1, 2000, 6, 1, false, "UTC"], t2000.to_a)

    t = Time.at(946684800).getlocal
    assert_equal(t.sec, Time.at(946684800).sec)
    assert_equal(t.min, Time.at(946684800).min)
    assert_equal(t.hour, Time.at(946684800).hour)
    assert_equal(t.mday, Time.at(946684800).mday)
    assert_equal(t.mon, Time.at(946684800).mon)
    assert_equal(t.year, Time.at(946684800).year)
    assert_equal(t.wday, Time.at(946684800).wday)
    assert_equal(t.yday, Time.at(946684800).yday)
    assert_equal(t.isdst, Time.at(946684800).isdst)
    assert_equal(t.zone, Time.at(946684800).zone)
    assert_zone_encoding(Time.at(946684800))
    assert_equal(t.gmt_offset, Time.at(946684800).gmt_offset)
    assert_equal(t.sunday?, Time.at(946684800).sunday?)
    assert_equal(t.monday?, Time.at(946684800).monday?)
    assert_equal(t.tuesday?, Time.at(946684800).tuesday?)
    assert_equal(t.wednesday?, Time.at(946684800).wednesday?)
    assert_equal(t.thursday?, Time.at(946684800).thursday?)
    assert_equal(t.friday?, Time.at(946684800).friday?)
    assert_equal(t.saturday?, Time.at(946684800).saturday?)
    assert_equal(t.to_a, Time.at(946684800).to_a)
  end

  def test_strftime
    t2000 = get_t2000
    t = Time.at(946684800).getlocal
    assert_equal("Sat", t2000.strftime("%a"))
    assert_equal("Saturday", t2000.strftime("%A"))
    assert_equal("Jan", t2000.strftime("%b"))
    assert_equal("January", t2000.strftime("%B"))
    assert_kind_of(String, t2000.strftime("%c"))
    assert_equal("01", t2000.strftime("%d"))
    assert_equal("00", t2000.strftime("%H"))
    assert_equal("12", t2000.strftime("%I"))
    assert_equal("001", t2000.strftime("%j"))
    assert_equal("01", t2000.strftime("%m"))
    assert_equal("00", t2000.strftime("%M"))
    assert_equal("AM", t2000.strftime("%p"))
    assert_equal("00", t2000.strftime("%S"))
    assert_equal("00", t2000.strftime("%U"))
    assert_equal("00", t2000.strftime("%W"))
    assert_equal("6", t2000.strftime("%w"))
    assert_equal("01/01/00", t2000.strftime("%x"))
    assert_equal("00:00:00", t2000.strftime("%X"))
    assert_equal("00", t2000.strftime("%y"))
    assert_equal("2000", t2000.strftime("%Y"))
    assert_equal("UTC", t2000.strftime("%Z"))
    assert_equal("%", t2000.strftime("%%"))
    assert_equal("0", t2000.strftime("%-S"))
    assert_equal("12:00:00 AM", t2000.strftime("%r"))
    assert_equal("Sat 2000-01-01T00:00:00", t2000.strftime("%3a %FT%T"))

    assert_warning(/strftime called with empty format string/) do
      assert_equal("", t2000.strftime(""))
    end
    assert_equal("foo\0bar\x0000\x0000\x0000", t2000.strftime("foo\0bar\0%H\0%M\0%S"))
    assert_equal("foo" * 1000, t2000.strftime("foo" * 1000))

    t = Time.mktime(2000, 1, 1)
    assert_equal("Sat", t.strftime("%a"))
  end

  def test_strftime_subsec
    t = Time.at(946684800, 123456.789)
    assert_equal("123", t.strftime("%3N"))
    assert_equal("123456", t.strftime("%6N"))
    assert_equal("123456789", t.strftime("%9N"))
    assert_equal("1234567890", t.strftime("%10N"))
    assert_equal("123456789", t.strftime("%0N"))
  end

  def test_strftime_sec
    t = get_t2000.getlocal
    assert_equal("000", t.strftime("%3S"))
  end

  def test_strftime_seconds_from_epoch
    t = Time.at(946684800, 123456.789)
    assert_equal("946684800", t.strftime("%s"))
    assert_equal("946684800", t.utc.strftime("%s"))

    t = Time.at(10000000000000000000000)
    assert_equal("<<10000000000000000000000>>", t.strftime("<<%s>>"))
    assert_equal("<<010000000000000000000000>>", t.strftime("<<%24s>>"))
    assert_equal("<<010000000000000000000000>>", t.strftime("<<%024s>>"))
    assert_equal("<< 10000000000000000000000>>", t.strftime("<<%_24s>>"))
  end

  def test_strftime_zone
    t = Time.mktime(2001, 10, 1)
    assert_equal("2001-10-01", t.strftime("%F"))
    assert_equal(Encoding::UTF_8, t.strftime("\u3042%Z").encoding)
    assert_equal(true, t.strftime("\u3042%Z").valid_encoding?)
  end

  def test_strftime_flags
    t = Time.mktime(2001, 10, 1, 2, 0, 0)
    assert_equal("01", t.strftime("%d"))
    assert_equal("01", t.strftime("%0d"))
    assert_equal(" 1", t.strftime("%_d"))
    assert_equal(" 1", t.strftime("%e"))
    assert_equal("01", t.strftime("%0e"))
    assert_equal(" 1", t.strftime("%_e"))
    assert_equal("AM", t.strftime("%p"))
    assert_equal("am", t.strftime("%#p"))
    assert_equal("am", t.strftime("%P"))
    assert_equal("AM", t.strftime("%#P"))
    assert_equal("02", t.strftime("%H"))
    assert_equal("02", t.strftime("%0H"))
    assert_equal(" 2", t.strftime("%_H"))
    assert_equal("02", t.strftime("%I"))
    assert_equal("02", t.strftime("%0I"))
    assert_equal(" 2", t.strftime("%_I"))
    assert_equal(" 2", t.strftime("%k"))
    assert_equal("02", t.strftime("%0k"))
    assert_equal(" 2", t.strftime("%_k"))
    assert_equal(" 2", t.strftime("%l"))
    assert_equal("02", t.strftime("%0l"))
    assert_equal(" 2", t.strftime("%_l"))
    t = Time.mktime(2001, 10, 1, 14, 0, 0)
    assert_equal("PM", t.strftime("%p"))
    assert_equal("pm", t.strftime("%#p"))
    assert_equal("pm", t.strftime("%P"))
    assert_equal("PM", t.strftime("%#P"))
    assert_equal("14", t.strftime("%H"))
    assert_equal("14", t.strftime("%0H"))
    assert_equal("14", t.strftime("%_H"))
    assert_equal("02", t.strftime("%I"))
    assert_equal("02", t.strftime("%0I"))
    assert_equal(" 2", t.strftime("%_I"))
    assert_equal("14", t.strftime("%k"))
    assert_equal("14", t.strftime("%0k"))
    assert_equal("14", t.strftime("%_k"))
    assert_equal(" 2", t.strftime("%l"))
    assert_equal("02", t.strftime("%0l"))
    assert_equal(" 2", t.strftime("%_l"))
    assert_equal("MON", t.strftime("%^a"))
    assert_equal("OCT", t.strftime("%^b"))

    t = get_t2000
    assert_equal("UTC", t.strftime("%^Z"))
    assert_equal("utc", t.strftime("%#Z"))
    assert_equal("SAT JAN  1 00:00:00 2000", t.strftime("%^c"))
  end

  def test_strftime_invalid_flags
    t = Time.mktime(2001, 10, 1, 2, 0, 0)
    assert_equal("%4^p", t.strftime("%4^p"), 'prec after flag')
  end

  def test_strftime_year
    t = Time.utc(1,1,4)
    assert_equal("0001", t.strftime("%Y"))
    assert_equal("0001", t.strftime("%G"))

    t = Time.utc(0,1,4)
    assert_equal("0000", t.strftime("%Y"))
    assert_equal("0000", t.strftime("%G"))

    t = Time.utc(-1,1,4)
    assert_equal("-0001", t.strftime("%Y"))
    assert_equal("-0001", t.strftime("%G"))

    t = Time.utc(10000000000000000000000,1,1)
    assert_equal("<<10000000000000000000000>>", t.strftime("<<%Y>>"))
    assert_equal("<<010000000000000000000000>>", t.strftime("<<%24Y>>"))
    assert_equal("<<010000000000000000000000>>", t.strftime("<<%024Y>>"))
    assert_equal("<< 10000000000000000000000>>", t.strftime("<<%_24Y>>"))
  end

  def test_strftime_weeknum
    # [ruby-dev:37155]
    t = Time.mktime(1970, 1, 18)
    assert_equal("0", t.strftime("%w"))
    assert_equal("7", t.strftime("%u"))
  end

  def test_strftime_ctrlchar
    # [ruby-dev:37160]
    t2000 = get_t2000
    assert_equal("\t", t2000.strftime("%t"))
    assert_equal("\t", t2000.strftime("%0t"))
    assert_equal("\t", t2000.strftime("%1t"))
    assert_equal("  \t", t2000.strftime("%3t"))
    assert_equal("00\t", t2000.strftime("%03t"))
    assert_equal("\n", t2000.strftime("%n"))
    assert_equal("\n", t2000.strftime("%0n"))
    assert_equal("\n", t2000.strftime("%1n"))
    assert_equal("  \n", t2000.strftime("%3n"))
    assert_equal("00\n", t2000.strftime("%03n"))
  end

  def test_strftime_weekflags
    # [ruby-dev:37162]
    t2000 = get_t2000
    assert_equal("SAT", t2000.strftime("%#a"))
    assert_equal("SATURDAY", t2000.strftime("%#A"))
    assert_equal("JAN", t2000.strftime("%#b"))
    assert_equal("JANUARY", t2000.strftime("%#B"))
    assert_equal("JAN", t2000.strftime("%#h"))
    assert_equal("FRIDAY", Time.local(2008,1,4).strftime("%#A"))
  end

  def test_strftime_rational
    t = Time.utc(2000,3,14, 6,53,"58.979323846".to_r) # Pi Day
    assert_equal("03/14/2000  6:53:58.97932384600000000000000000000",
                 t.strftime("%m/%d/%Y %l:%M:%S.%29N"))
    assert_equal("03/14/2000  6:53:58.9793238460",
                 t.strftime("%m/%d/%Y %l:%M:%S.%10N"))
    assert_equal("03/14/2000  6:53:58.979323846",
                 t.strftime("%m/%d/%Y %l:%M:%S.%9N"))
    assert_equal("03/14/2000  6:53:58.97932384",
                 t.strftime("%m/%d/%Y %l:%M:%S.%8N"))

    t = Time.utc(1592,3,14, 6,53,"58.97932384626433832795028841971".to_r) # Pi Day
    assert_equal("03/14/1592  6:53:58.97932384626433832795028841971",
                 t.strftime("%m/%d/%Y %l:%M:%S.%29N"))
    assert_equal("03/14/1592  6:53:58.9793238462",
                 t.strftime("%m/%d/%Y %l:%M:%S.%10N"))
    assert_equal("03/14/1592  6:53:58.979323846",
                 t.strftime("%m/%d/%Y %l:%M:%S.%9N"))
    assert_equal("03/14/1592  6:53:58.97932384",
                 t.strftime("%m/%d/%Y %l:%M:%S.%8N"))
  end

  def test_strftime_far_future
    # [ruby-core:33985]
    assert_equal("3000000000", Time.at(3000000000).strftime('%s'))
  end

  def test_strftime_too_wide
    assert_equal(8192, Time.now.strftime('%8192z').size)
  end

  def test_strftime_wide_precision
    t2000 = get_t2000
    s = t2000.strftime("%28c")
    assert_equal(28, s.size)
    assert_equal(t2000.strftime("%c"), s.strip)
  end

  def test_strfimte_zoneoffset
    t2000 = get_t2000
    t = t2000.getlocal("+09:00:00")
    assert_equal("+0900", t.strftime("%z"))
    assert_equal("+09:00", t.strftime("%:z"))
    assert_equal("+09:00:00", t.strftime("%::z"))
    assert_equal("+09", t.strftime("%:::z"))

    t = t2000.getlocal("+09:00:01")
    assert_equal("+0900", t.strftime("%z"))
    assert_equal("+09:00", t.strftime("%:z"))
    assert_equal("+09:00:01", t.strftime("%::z"))
    assert_equal("+09:00:01", t.strftime("%:::z"))

    assert_equal("+0000", t2000.strftime("%z"))
    assert_equal("-0000", t2000.strftime("%-z"))
    assert_equal("-00:00", t2000.strftime("%-:z"))
    assert_equal("-00:00:00", t2000.strftime("%-::z"))

    t = t2000.getlocal("+00:00")
    assert_equal("+0000", t.strftime("%z"))
    assert_equal("+0000", t.strftime("%-z"))
    assert_equal("+00:00", t.strftime("%-:z"))
    assert_equal("+00:00:00", t.strftime("%-::z"))
  end

  def test_strftime_padding
    bug4458 = '[ruby-dev:43287]'
    t2000 = get_t2000
    t = t2000.getlocal("+09:00")
    assert_equal("+0900", t.strftime("%z"))
    assert_equal("+09:00", t.strftime("%:z"))
    assert_equal("      +900", t.strftime("%_10z"), bug4458)
    assert_equal("+000000900", t.strftime("%10z"), bug4458)
    assert_equal("     +9:00", t.strftime("%_10:z"), bug4458)
    assert_equal("+000009:00", t.strftime("%10:z"), bug4458)
    assert_equal("  +9:00:00", t.strftime("%_10::z"), bug4458)
    assert_equal("+009:00:00", t.strftime("%10::z"), bug4458)
    assert_equal("+000000009", t.strftime("%10:::z"))
    t = t2000.getlocal("-05:00")
    assert_equal("-0500", t.strftime("%z"))
    assert_equal("-05:00", t.strftime("%:z"))
    assert_equal("      -500", t.strftime("%_10z"), bug4458)
    assert_equal("-000000500", t.strftime("%10z"), bug4458)
    assert_equal("     -5:00", t.strftime("%_10:z"), bug4458)
    assert_equal("-000005:00", t.strftime("%10:z"), bug4458)
    assert_equal("  -5:00:00", t.strftime("%_10::z"), bug4458)
    assert_equal("-005:00:00", t.strftime("%10::z"), bug4458)
    assert_equal("-000000005", t.strftime("%10:::z"))

    bug6323 = '[ruby-core:44447]'
    t = t2000.getlocal("+00:36")
    assert_equal("      +036", t.strftime("%_10z"), bug6323)
    assert_equal("+000000036", t.strftime("%10z"), bug6323)
    assert_equal("     +0:36", t.strftime("%_10:z"), bug6323)
    assert_equal("+000000:36", t.strftime("%10:z"), bug6323)
    assert_equal("  +0:36:00", t.strftime("%_10::z"), bug6323)
    assert_equal("+000:36:00", t.strftime("%10::z"), bug6323)
    assert_equal("+000000:36", t.strftime("%10:::z"))
    t = t2000.getlocal("-00:55")
    assert_equal("      -055", t.strftime("%_10z"), bug6323)
    assert_equal("-000000055", t.strftime("%10z"), bug6323)
    assert_equal("     -0:55", t.strftime("%_10:z"), bug6323)
    assert_equal("-000000:55", t.strftime("%10:z"), bug6323)
    assert_equal("  -0:55:00", t.strftime("%_10::z"), bug6323)
    assert_equal("-000:55:00", t.strftime("%10::z"), bug6323)
    assert_equal("-000000:55", t.strftime("%10:::z"))
  end

  def test_strftime_invalid_modifier
    t2000 = get_t2000
    t = t2000.getlocal("+09:00")
    assert_equal("%:y", t.strftime("%:y"), 'invalid conversion after : modifier')
    assert_equal("%:0z", t.strftime("%:0z"), 'flag after : modifier')
    assert_equal("%:10z", t.strftime("%:10z"), 'prec after : modifier')
    assert_equal("%Ob", t.strftime("%Ob"), 'invalid conversion after locale modifier')
    assert_equal("%Eb", t.strftime("%Eb"), 'invalid conversion after locale modifier')
    assert_equal("%O0y", t.strftime("%O0y"), 'flag after locale modifier')
    assert_equal("%E0y", t.strftime("%E0y"), 'flag after locale modifier')
    assert_equal("%O10y", t.strftime("%O10y"), 'prec after locale modifier')
    assert_equal("%E10y", t.strftime("%E10y"), 'prec after locale modifier')
  end

  def test_delegate
    d1 = SimpleDelegator.new(t1 = Time.utc(2000))
    d2 = SimpleDelegator.new(t2 = Time.utc(2001))
    assert_equal(-1, t1 <=> t2)
    assert_equal(1, t2 <=> t1)
    assert_equal(-1, d1 <=> d2)
    assert_equal(1, d2 <=> d1)
  end

  def test_to_r
    assert_kind_of(Rational, Time.new(2000,1,1,0,0,Rational(4,3)).to_r)
    assert_kind_of(Rational, Time.utc(1970).to_r)
  end

  def test_round
    t = Time.utc(1999,12,31, 23,59,59)
    t2 = (t+0.4).round
    assert_equal([59,59,23, 31,12,1999, 5,365,false,"UTC"], t2.to_a)
    assert_equal(0, t2.subsec)
    t2 = (t+0.49).round
    assert_equal([59,59,23, 31,12,1999, 5,365,false,"UTC"], t2.to_a)
    assert_equal(0, t2.subsec)
    t2 = (t+0.5).round
    assert_equal([0,0,0, 1,1,2000, 6,1,false,"UTC"], t2.to_a)
    assert_equal(0, t2.subsec)
    t2 = (t+1.4).round
    assert_equal([0,0,0, 1,1,2000, 6,1,false,"UTC"], t2.to_a)
    assert_equal(0, t2.subsec)
    t2 = (t+1.49).round
    assert_equal([0,0,0, 1,1,2000, 6,1,false,"UTC"], t2.to_a)
    assert_equal(0, t2.subsec)
    t2 = (t+1.5).round
    assert_equal([1,0,0, 1,1,2000, 6,1,false,"UTC"], t2.to_a)
    assert_equal(0, t2.subsec)

    t2 = (t+0.123456789).round(4)
    assert_equal([59,59,23, 31,12,1999, 5,365,false,"UTC"], t2.to_a)
    assert_equal(Rational(1235,10000), t2.subsec)

    off = 0.0
    100.times {|i|
      t2 = (t+off).round(1)
      assert_equal(Rational(i % 10, 10), t2.subsec)
      off += 0.1
    }
  end

  def test_floor
    t = Time.utc(1999,12,31, 23,59,59)
    t2 = (t+0.4).floor
    assert_equal([59,59,23, 31,12,1999, 5,365,false,"UTC"], t2.to_a)
    assert_equal(0, t2.subsec)
    t2 = (t+0.49).floor
    assert_equal([59,59,23, 31,12,1999, 5,365,false,"UTC"], t2.to_a)
    assert_equal(0, t2.subsec)
    t2 = (t+0.5).floor
    assert_equal([59,59,23, 31,12,1999, 5,365,false,"UTC"], t2.to_a)
    assert_equal(0, t2.subsec)
    t2 = (t+1.4).floor
    assert_equal([0,0,0, 1,1,2000, 6,1,false,"UTC"], t2.to_a)
    assert_equal(0, t2.subsec)
    t2 = (t+1.49).floor
    assert_equal([0,0,0, 1,1,2000, 6,1,false,"UTC"], t2.to_a)
    assert_equal(0, t2.subsec)
    t2 = (t+1.5).floor
    assert_equal([0,0,0, 1,1,2000, 6,1,false,"UTC"], t2.to_a)
    assert_equal(0, t2.subsec)

    t2 = (t+0.123456789).floor(4)
    assert_equal([59,59,23, 31,12,1999, 5,365,false,"UTC"], t2.to_a)
    assert_equal(Rational(1234,10000), t2.subsec)
  end

  def test_ceil
    t = Time.utc(1999,12,31, 23,59,59)
    t2 = (t+0.4).ceil
    assert_equal([0,0,0, 1,1,2000, 6,1,false,"UTC"], t2.to_a)
    assert_equal(0, t2.subsec)
    t2 = (t+0.49).ceil
    assert_equal([0,0,0, 1,1,2000, 6,1,false,"UTC"], t2.to_a)
    assert_equal(0, t2.subsec)
    t2 = (t+0.5).ceil
    assert_equal([0,0,0, 1,1,2000, 6,1,false,"UTC"], t2.to_a)
    assert_equal(0, t2.subsec)
    t2 = (t+1.4).ceil
    assert_equal([1,0,0, 1,1,2000, 6,1,false,"UTC"], t2.to_a)
    assert_equal(0, t2.subsec)
    t2 = (t+1.49).ceil
    assert_equal([1,0,0, 1,1,2000, 6,1,false,"UTC"], t2.to_a)
    assert_equal(0, t2.subsec)
    t2 = (t+1.5).ceil
    assert_equal([1,0,0, 1,1,2000, 6,1,false,"UTC"], t2.to_a)
    assert_equal(0, t2.subsec)

    t2 = (t+0.123456789).ceil(4)
    assert_equal([59,59,23, 31,12,1999, 5,365,false,"UTC"], t2.to_a)
    assert_equal(Rational(1235,10000), t2.subsec)

    time = Time.utc(2016, 4, 23, 0, 0, 0.123456789r)
    assert_equal(time, time.ceil(9))
    assert_equal(time, time.ceil(10))
    assert_equal(time, time.ceil(11))
  end

  def test_getlocal_dont_share_eigenclass
    bug5012 = "[ruby-dev:44071]"

    t0 = Time.now
    class << t0; end
    t1 = t0.getlocal

    def t0.m
      0
    end

    assert_raise(NoMethodError, bug5012) { t1.m }
  end

  def test_sec_str
    bug6193 = '[ruby-core:43569]'
    t = nil
    assert_nothing_raised(bug6193) {t = Time.new(2012, 1, 2, 3, 4, "5")}
    assert_equal(Time.new(2012, 1, 2, 3, 4, 5), t, bug6193)
  end

  def test_past
    [
      [-(1 << 100), 1, 1, 0, 0, 0],
      [-4000, 1, 1, 0, 0, 0],
      [-3000, 1, 1, 0, 0, 0],
    ].each {|year, mon, day, hour, min, sec|
      t = Time.utc(year, mon, day, hour, min, sec)
      assert_equal(year, t.year)
      assert_equal(mon, t.mon)
      assert_equal(day, t.day)
      assert_equal(hour, t.hour)
      assert_equal(min, t.min)
      assert_equal(sec, t.sec)
    }
  end

  def test_1901
    assert_equal(-0x80000001, Time.utc(1901, 12, 13, 20, 45, 51).tv_sec)
    [
      [1901, 12, 13, 20, 45, 50],
      [1901, 12, 13, 20, 45, 51],
      [1901, 12, 13, 20, 45, 52], # -0x80000000
      [1901, 12, 13, 20, 45, 53],
    ].each {|year, mon, day, hour, min, sec|
      t = Time.utc(year, mon, day, hour, min, sec)
      assert_equal(year, t.year)
      assert_equal(mon, t.mon)
      assert_equal(day, t.day)
      assert_equal(hour, t.hour)
      assert_equal(min, t.min)
      assert_equal(sec, t.sec)
    }
  end

  def test_1970
    assert_equal(0, Time.utc(1970, 1, 1, 0, 0, 0).tv_sec)
    [
      [1969, 12, 31, 23, 59, 59],
      [1970, 1, 1, 0, 0, 0],
      [1970, 1, 1, 0, 0, 1],
    ].each {|year, mon, day, hour, min, sec|
      t = Time.utc(year, mon, day, hour, min, sec)
      assert_equal(year, t.year)
      assert_equal(mon, t.mon)
      assert_equal(day, t.day)
      assert_equal(hour, t.hour)
      assert_equal(min, t.min)
      assert_equal(sec, t.sec)
    }
  end

  def test_2038
    # Giveup to try 2nd test because some state is changed.
    omit if Test::Unit::Runner.current_repeat_count > 0

    if no_leap_seconds?
      assert_equal(0x80000000, Time.utc(2038, 1, 19, 3, 14, 8).tv_sec)
    end
    [
      [2038, 1, 19, 3, 14, 7],
      [2038, 1, 19, 3, 14, 8],
      [2038, 1, 19, 3, 14, 9],
      [2039, 1, 1, 0, 0, 0],
    ].each {|year, mon, day, hour, min, sec|
      t = Time.utc(year, mon, day, hour, min, sec)
      assert_equal(year, t.year)
      assert_equal(mon, t.mon)
      assert_equal(day, t.day)
      assert_equal(hour, t.hour)
      assert_equal(min, t.min)
      assert_equal(sec, t.sec)
    }
    assert_equal(Time.local(2038,3,1), Time.local(2038,2,29))
    assert_equal(Time.local(2038,3,2), Time.local(2038,2,30))
    assert_equal(Time.local(2038,3,3), Time.local(2038,2,31))
    assert_equal(Time.local(2040,2,29), Time.local(2040,2,29))
    assert_equal(Time.local(2040,3,1), Time.local(2040,2,30))
    assert_equal(Time.local(2040,3,2), Time.local(2040,2,31))
    n = 2 ** 64
    n += 400 - n % 400 # n is over 2^64 and multiple of 400
    assert_equal(Time.local(n,2,29),Time.local(n,2,29))
    assert_equal(Time.local(n,3,1), Time.local(n,2,30))
    assert_equal(Time.local(n,3,2), Time.local(n,2,31))
    n += 100
    assert_equal(Time.local(n,3,1), Time.local(n,2,29))
    assert_equal(Time.local(n,3,2), Time.local(n,2,30))
    assert_equal(Time.local(n,3,3), Time.local(n,2,31))
    n += 4
    assert_equal(Time.local(n,2,29),Time.local(n,2,29))
    assert_equal(Time.local(n,3,1), Time.local(n,2,30))
    assert_equal(Time.local(n,3,2), Time.local(n,2,31))
    n += 1
    assert_equal(Time.local(n,3,1), Time.local(n,2,29))
    assert_equal(Time.local(n,3,2), Time.local(n,2,30))
    assert_equal(Time.local(n,3,3), Time.local(n,2,31))
  end

  def test_future
    [
      [3000, 1, 1, 0, 0, 0],
      [4000, 1, 1, 0, 0, 0],
      [1 << 100, 1, 1, 0, 0, 0],
    ].each {|year, mon, day, hour, min, sec|
      t = Time.utc(year, mon, day, hour, min, sec)
      assert_equal(year, t.year)
      assert_equal(mon, t.mon)
      assert_equal(day, t.day)
      assert_equal(hour, t.hour)
      assert_equal(min, t.min)
      assert_equal(sec, t.sec)
    }
  end

  def test_getlocal_utc
    t = Time.gm(2000)
    assert_equal [00, 00, 00,  1,  1, 2000], (t1 = t.getlocal("UTC")).to_a[0, 6]
    assert_predicate t1, :utc?
    assert_equal [00, 00, 00,  1,  1, 2000], (t1 = t.getlocal("-0000")).to_a[0, 6]
    assert_predicate t1, :utc?
    assert_equal [00, 00, 00,  1,  1, 2000], (t1 = t.getlocal("+0000")).to_a[0, 6]
    assert_not_predicate t1, :utc?
  end

  def test_getlocal_utc_offset
    t = Time.gm(2000)
    assert_equal [00, 30, 21, 31, 12, 1999], t.getlocal("-02:30").to_a[0, 6]
    assert_equal [00, 00,  9,  1,  1, 2000], t.getlocal("+09:00").to_a[0, 6]
    assert_equal [20, 29, 21, 31, 12, 1999], t.getlocal("-02:30:40").to_a[0, 6]
    assert_equal [35, 10,  9,  1,  1, 2000], t.getlocal("+09:10:35").to_a[0, 6]
    assert_equal [00, 30, 21, 31, 12, 1999], t.getlocal("-0230").to_a[0, 6]
    assert_equal [00, 00,  9,  1,  1, 2000], t.getlocal("+0900").to_a[0, 6]
    assert_equal [20, 29, 21, 31, 12, 1999], t.getlocal("-023040").to_a[0, 6]
    assert_equal [35, 10,  9,  1,  1, 2000], t.getlocal("+091035").to_a[0, 6]
    assert_raise(ArgumentError) {t.getlocal("-02:3040")}
    assert_raise(ArgumentError) {t.getlocal("+0910:35")}
  end

  def test_getlocal_nil
    now = Time.now
    now2 = nil
    now3 = nil
    assert_nothing_raised {
      now2 = now.getlocal
      now3 = now.getlocal(nil)
    }
    assert_equal now2, now3
    assert_equal now2.zone, now3.zone
  end

  def test_strftime_yearday_on_last_day_of_year
    t = Time.utc(2015, 12, 31, 0, 0, 0)
    assert_equal("365", t.strftime("%j"))
    t = Time.utc(2016, 12, 31, 0, 0, 0)
    assert_equal("366", t.strftime("%j"))

    t = Time.utc(2015, 12, 30, 20, 0, 0).getlocal("+05:00")
    assert_equal("365", t.strftime("%j"))
    t = Time.utc(2016, 12, 30, 20, 0, 0).getlocal("+05:00")
    assert_equal("366", t.strftime("%j"))

    t = Time.utc(2016, 1, 1, 1, 0, 0).getlocal("-05:00")
    assert_equal("365", t.strftime("%j"))
    t = Time.utc(2017, 1, 1, 1, 0, 0).getlocal("-05:00")
    assert_equal("366", t.strftime("%j"))
  end

  def test_num_exact_error
    bad = EnvUtil.labeled_class("BadValue").new
    x = EnvUtil.labeled_class("Inexact") do
      def to_s; "Inexact"; end
      define_method(:to_int) {bad}
      define_method(:to_r) {bad}
    end.new
    assert_raise_with_message(TypeError, /Inexact/) {Time.at(x)}
  end

  def test_memsize
    # Time objects are common in some code, try to keep them small
    omit "Time object size test" if /^(?:i.?86|x86_64)-linux/ !~ RUBY_PLATFORM
    omit "GC is in debug" if GC::INTERNAL_CONSTANTS[:DEBUG]
    require 'objspace'
    t = Time.at(0)
    sizeof_timew =
      if RbConfig::SIZEOF.key?("uint64_t") && RbConfig::SIZEOF["long"] * 2 <= RbConfig::SIZEOF["uint64_t"]
        RbConfig::SIZEOF["uint64_t"]
      else
        RbConfig::SIZEOF["void*"] # Same size as VALUE
      end
    sizeof_vtm = RbConfig::SIZEOF["void*"] * 4 + 8
    expect = GC::INTERNAL_CONSTANTS[:BASE_SLOT_SIZE] + sizeof_timew + sizeof_vtm
    assert_equal expect, ObjectSpace.memsize_of(t)
  rescue LoadError => e
    omit "failed to load objspace: #{e.message}"
  end

  def test_deconstruct_keys
    t = in_timezone('JST-9') { Time.local(2022, 10, 16, 14, 1, 30, 500) }
    assert_equal(
      {year: 2022, month: 10, day: 16, wday: 0, yday: 289,
        hour: 14, min: 1, sec: 30, subsec: 1/2000r, dst: false, zone: 'JST'},
      t.deconstruct_keys(nil)
    )

    assert_equal(
      {year: 2022, month: 10, sec: 30},
      t.deconstruct_keys(%i[year month sec nonexistent])
    )
  end

  def test_parse_zero_bigint
    assert_equal 0, Time.new("2020-10-28T16:48:07.000Z").nsec, '[Bug #19390]'
  end
end
