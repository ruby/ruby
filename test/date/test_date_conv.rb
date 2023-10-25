# frozen_string_literal: true
require 'test/unit'
require 'date'

class TestDateConv < Test::Unit::TestCase
  def with_tz(tz)
    old = ENV["TZ"]
    begin
      ENV["TZ"] = tz
      yield
    ensure
      ENV["TZ"] = old
    end
  end

  def test_to_class
    [Time.now, Date.today, DateTime.now].each do |o|
      assert_instance_of(Time, o.to_time)
      assert_instance_of(Date, o.to_date)
      assert_instance_of(DateTime, o.to_datetime)
    end
  end

  def test_to_time__from_time
    t = Time.mktime(2004, 9, 19, 1, 2, 3, 456789)
    t2 = t.to_time
    assert_equal([2004, 9, 19, 1, 2, 3, 456789],
		 [t2.year, t2.mon, t2.mday, t2.hour, t2.min, t2.sec, t2.usec])

    t = Time.utc(2004, 9, 19, 1, 2, 3, 456789)
    t2 = t.to_time.utc
    assert_equal([2004, 9, 19, 1, 2, 3, 456789],
		 [t2.year, t2.mon, t2.mday, t2.hour, t2.min, t2.sec, t2.usec])

    t = Time.new(2004, 9, 19, 1, 2, 3, '+03:00')
    with_tz('Asia/Tokyo') do
      t2 = t.to_time
      assert_equal([2004, 9, 19, 1, 2, 3],
       [t2.year, t2.mon, t2.mday, t2.hour, t2.min, t2.sec])
      assert_equal(3 * 60 * 60, t2.gmt_offset)
    end
  end

  def test_to_time__from_date
    d = Date.new(2004, 9, 19)
    t = d.to_time
    assert_equal([2004, 9, 19, 0, 0, 0, 0],
		 [t.year, t.mon, t.mday, t.hour, t.min, t.sec, t.usec])
  end

  def test_to_time_to_date_roundtrip__from_gregorian_date
    d = Date.new(1582, 10, 15)
    t = d.to_time
    assert_equal([1582, 10, 15, 0, 0, 0, 0],
		 [t.year, t.mon, t.mday, t.hour, t.min, t.sec, t.usec])
    assert_equal(d, t.to_date)
    assert_equal(d.jd, t.to_date.jd)
  end

  def test_to_time_to_date_roundtrip__from_julian_date
    d = Date.new(1582, 10, 4)
    t = d.to_time
    assert_equal([1582, 10, 14, 0, 0, 0, 0],
		 [t.year, t.mon, t.mday, t.hour, t.min, t.sec, t.usec])
    assert_equal(d, t.to_date)
    assert_equal(d.jd, t.to_date.jd)
  end

  def test_to_time__from_datetime
    d = DateTime.new(2004, 9, 19, 1, 2, 3, 8.to_r/24) + 456789.to_r/86400000000
    t = d.to_time
    assert_equal([2004, 9, 19, 1, 2, 3, 456789, 8*60*60],
     [t.year, t.mon, t.mday, t.hour, t.min, t.sec, t.usec, t.utc_offset])

    d = DateTime.new(2004, 9, 19, 1, 2, 3, 0) + 456789.to_r/86400000000
    t = d.to_time.utc
    assert_equal([2004, 9, 19, 1, 2, 3, 456789],
		 [t.year, t.mon, t.mday, t.hour, t.min, t.sec, t.usec])

    d = DateTime.new(1582, 10, 3, 1, 2, 3, 0) + 456789.to_r/86400000000
    t = d.to_time.utc
    assert_equal([1582, 10, 13, 1, 2, 3, 456789],
		 [t.year, t.mon, t.mday, t.hour, t.min, t.sec, t.usec])

    if Time.allocate.respond_to?(:nsec)
      d = DateTime.new(2004, 9, 19, 1, 2, 3, 0) + 456789123.to_r/86400000000000
      t = d.to_time.utc
      assert_equal([2004, 9, 19, 1, 2, 3, 456789123],
		   [t.year, t.mon, t.mday, t.hour, t.min, t.sec, t.nsec])
    end

    if Time.allocate.respond_to?(:subsec)
      d = DateTime.new(2004, 9, 19, 1, 2, 3, 0) + 456789123456789123.to_r/86400000000000000000000
      t = d.to_time.utc
      assert_equal([2004, 9, 19, 1, 2, 3, Rational(456789123456789123,1000000000000000000)],
		   [t.year, t.mon, t.mday, t.hour, t.min, t.sec, t.subsec])
    end
  end

  def test_to_date__from_time
    t = Time.mktime(2004, 9, 19, 1, 2, 3, 456789)
    d = t.to_date
    assert_equal([2004, 9, 19, 0], [d.year, d.mon, d.mday, d.day_fraction])

    t = Time.utc(2004, 9, 19, 1, 2, 3, 456789)
    d = t.to_date
    assert_equal([2004, 9, 19, 0], [d.year, d.mon, d.mday, d.day_fraction])

    t = Time.utc(1582, 10, 13, 1, 2, 3, 456789)
    d = t.to_date # using ITALY
    assert_equal([1582, 10, 3, 0], [d.year, d.mon, d.mday, d.day_fraction])
  end

  def test_to_date__from_date
    d = Date.new(2004, 9, 19) + 1.to_r/2
    d2 = d.to_date
    assert_equal([2004, 9, 19, 1.to_r/2],
		 [d2.year, d2.mon, d2.mday, d2.day_fraction])
  end

  def test_to_date__from_datetime
    d = DateTime.new(2004, 9, 19, 1, 2, 3, 9.to_r/24) + 456789.to_r/86400000000
    d2 = d.to_date
    assert_equal([2004, 9, 19, 0], [d2.year, d2.mon, d2.mday, d2.day_fraction])

    d = DateTime.new(2004, 9, 19, 1, 2, 3, 0) + 456789.to_r/86400000000
    d2 = d.to_date
    assert_equal([2004, 9, 19, 0], [d2.year, d2.mon, d2.mday, d2.day_fraction])
  end

  def test_to_datetime__from_time
    t = Time.mktime(2004, 9, 19, 1, 2, 3, 456789)
    d = t.to_datetime
    assert_equal([2004, 9, 19, 1, 2, 3,
		  456789.to_r/1000000,
		  t.utc_offset.to_r/86400],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec,
		  d.sec_fraction, d.offset])

    t = Time.utc(2004, 9, 19, 1, 2, 3, 456789)
    d = t.to_datetime
    assert_equal([2004, 9, 19, 1, 2, 3,
		  456789.to_r/1000000,
		  0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec,
		  d.sec_fraction, d.offset])

    t = Time.utc(1582, 10, 13, 1, 2, 3, 456789)
    d = t.to_datetime # using ITALY
    assert_equal([1582, 10, 3, 1, 2, 3,
		  456789.to_r/1000000,
		  0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec,
		  d.sec_fraction, d.offset])

    t = Time.now
    d = t.to_datetime
    require 'time'
    assert_equal(t.iso8601(10), d.iso8601(10))
  end

  def test_to_datetime__from_date
    d = Date.new(2004, 9, 19) + 1.to_r/2
    d2 = d.to_datetime
    assert_equal([2004, 9, 19, 0, 0, 0, 0, 0],
		 [d2.year, d2.mon, d2.mday, d2.hour, d2.min, d2.sec,
		  d2.sec_fraction, d2.offset])
  end

  def test_to_datetime__from_datetime
    d = DateTime.new(2004, 9, 19, 1, 2, 3, 9.to_r/24) + 456789.to_r/86400000000
    d2 = d.to_datetime
    assert_equal([2004, 9, 19, 1, 2, 3,
		  456789.to_r/1000000,
		  9.to_r/24],
		 [d2.year, d2.mon, d2.mday, d2.hour, d2.min, d2.sec,
		  d2.sec_fraction, d2.offset])

    d = DateTime.new(2004, 9, 19, 1, 2, 3, 0) + 456789.to_r/86400000000
    d2 = d.to_datetime
    assert_equal([2004, 9, 19, 1, 2, 3,
		  456789.to_r/1000000,
		  0],
		 [d2.year, d2.mon, d2.mday, d2.hour, d2.min, d2.sec,
		  d2.sec_fraction, d2.offset])
  end

end
