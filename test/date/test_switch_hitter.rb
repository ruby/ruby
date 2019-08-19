# frozen_string_literal: true
require 'test/unit'
require 'date'

class TestSH < Test::Unit::TestCase

  def test_new
    [Date.new,
     Date.civil,
     DateTime.new,
     DateTime.civil
	].each do |d|
      assert_equal([-4712, 1, 1], [d.year, d.mon, d.mday])
    end

    [Date.new(2001),
     Date.civil(2001),
     DateTime.new(2001),
     DateTime.civil(2001)
	].each do |d|
      assert_equal([2001, 1, 1], [d.year, d.mon, d.mday])
    end

    d = Date.new(2001, 2, 3)
    assert_equal([2001, 2, 3], [d.year, d.mon, d.mday])
    d = Date.new(2001, 2, Rational('3.5'))
    assert_equal([2001, 2, 3], [d.year, d.mon, d.mday])
    d = Date.new(2001,2, 3, Date::JULIAN)
    assert_equal([2001, 2, 3], [d.year, d.mon, d.mday])
    d = Date.new(2001,2, 3, Date::GREGORIAN)
    assert_equal([2001, 2, 3], [d.year, d.mon, d.mday])

    d = Date.new(2001,-12, -31)
    assert_equal([2001, 1, 1], [d.year, d.mon, d.mday])
    d = Date.new(2001,-12, -31, Date::JULIAN)
    assert_equal([2001, 1, 1], [d.year, d.mon, d.mday])
    d = Date.new(2001,-12, -31, Date::GREGORIAN)
    assert_equal([2001, 1, 1], [d.year, d.mon, d.mday])

    d = DateTime.new(2001, 2, 3, 4, 5, 6)
    assert_equal([2001, 2, 3, 4, 5, 6, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.new(2001, 2, 3, 4, 5, 6, 0)
    assert_equal([2001, 2, 3, 4, 5, 6, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.new(2001, 2, 3, 4, 5, 6, Rational(9,24))
    assert_equal([2001, 2, 3, 4, 5, 6, Rational(9,24)],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.new(2001, 2, 3, 4, 5, 6, 0.375)
    assert_equal([2001, 2, 3, 4, 5, 6, Rational(9,24)],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.new(2001, 2, 3, 4, 5, 6, '+09:00')
    assert_equal([2001, 2, 3, 4, 5, 6, Rational(9,24)],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.new(2001, 2, 3, 4, 5, 6, '-09:00')
    assert_equal([2001, 2, 3, 4, 5, 6, Rational(-9,24)],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.new(2001, -12, -31, -4, -5, -6, '-09:00')
    assert_equal([2001, 1, 1, 20, 55, 54, Rational(-9,24)],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.new(2001, -12, -31, -4, -5, -6, '-09:00', Date::JULIAN)
    assert_equal([2001, 1, 1, 20, 55, 54, Rational(-9,24)],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.new(2001, -12, -31, -4, -5, -6, '-09:00', Date::GREGORIAN)
    assert_equal([2001, 1, 1, 20, 55, 54, Rational(-9,24)],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
  end

  def test_jd
    d = Date.jd
    assert_equal([-4712, 1, 1], [d.year, d.mon, d.mday])
    d = Date.jd(0)
    assert_equal([-4712, 1, 1], [d.year, d.mon, d.mday])
    d = Date.jd(2451944)
    assert_equal([2001, 2, 3], [d.year, d.mon, d.mday])

    d = DateTime.jd
    assert_equal([-4712, 1, 1, 0, 0, 0, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.jd(0)
    assert_equal([-4712, 1, 1, 0, 0, 0, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.jd(2451944)
    assert_equal([2001, 2, 3, 0, 0, 0, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.jd(2451944, 4, 5, 6)
    assert_equal([2001, 2, 3, 4, 5, 6, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.jd(2451944, 4, 5, 6, 0)
    assert_equal([2001, 2, 3, 4, 5, 6, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.jd(2451944, 4, 5, 6, '+9:00')
    assert_equal([2001, 2, 3, 4, 5, 6, Rational(9, 24)],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.jd(2451944, -4, -5, -6, '-9:00')
    assert_equal([2001, 2, 3, 20, 55, 54, Rational(-9, 24)],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
  end

  def test_ordinal
    d = Date.ordinal
    assert_equal([-4712, 1], [d.year, d.yday])
    d = Date.ordinal(-4712, 1)
    assert_equal([-4712, 1], [d.year, d.yday])

    d = Date.ordinal(2001, 2)
    assert_equal([2001, 2], [d.year, d.yday])
    d = Date.ordinal(2001, 2, Date::JULIAN)
    assert_equal([2001, 2], [d.year, d.yday])
    d = Date.ordinal(2001, 2, Date::GREGORIAN)
    assert_equal([2001, 2], [d.year, d.yday])

    d = Date.ordinal(2001, -2, Date::JULIAN)
    assert_equal([2001, 364], [d.year, d.yday])
    d = Date.ordinal(2001, -2, Date::GREGORIAN)
    assert_equal([2001, 364], [d.year, d.yday])

    d = DateTime.ordinal
    assert_equal([-4712, 1, 1, 0, 0, 0, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.ordinal(-4712, 1)
    assert_equal([-4712, 1, 1, 0, 0, 0, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.ordinal(2001, 34)
    assert_equal([2001, 2, 3, 0, 0, 0, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.ordinal(2001, 34, 4, 5, 6)
    assert_equal([2001, 2, 3, 4, 5, 6, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.ordinal(2001, 34, 4, 5, 6, 0)
    assert_equal([2001, 2, 3, 4, 5, 6, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.ordinal(2001, 34, 4, 5, 6, '+9:00')
    assert_equal([2001, 2, 3, 4, 5, 6, Rational(9, 24)],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.ordinal(2001, 34, -4, -5, -6, '-9:00')
    assert_equal([2001, 2, 3, 20, 55, 54, Rational(-9, 24)],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
  end

  def test_commercial
    d = Date.commercial
    assert_equal([-4712, 1, 1], [d.cwyear, d.cweek, d.cwday])
    d = Date.commercial(-4712, 1, 1)
    assert_equal([-4712, 1, 1], [d.cwyear, d.cweek, d.cwday])

    d = Date.commercial(2001, 2, 3)
    assert_equal([2001, 2, 3], [d.cwyear, d.cweek, d.cwday])
    d = Date.commercial(2001, 2, 3, Date::JULIAN)
    assert_equal([2001, 2, 3], [d.cwyear, d.cweek, d.cwday])
    d = Date.commercial(2001, 2, 3, Date::GREGORIAN)
    assert_equal([2001, 2, 3], [d.cwyear, d.cweek, d.cwday])

    d = Date.commercial(2001, -2, -3)
    assert_equal([2001, 51, 5], [d.cwyear, d.cweek, d.cwday])
    d = Date.commercial(2001, -2, -3, Date::JULIAN)
    assert_equal([2001, 51, 5], [d.cwyear, d.cweek, d.cwday])
    d = Date.commercial(2001, -2, -3, Date::GREGORIAN)
    assert_equal([2001, 51, 5], [d.cwyear, d.cweek, d.cwday])

    d = DateTime.commercial
    assert_equal([-4712, 1, 1, 0, 0, 0, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.commercial(-4712, 1, 1)
    assert_equal([-4712, 1, 1, 0, 0, 0, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.commercial(2001, 5, 6)
    assert_equal([2001, 2, 3, 0, 0, 0, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.commercial(2001, 5, 6, 4, 5, 6)
    assert_equal([2001, 2, 3, 4, 5, 6, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.commercial(2001, 5, 6, 4, 5, 6, 0)
    assert_equal([2001, 2, 3, 4, 5, 6, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.commercial(2001, 5, 6, 4, 5, 6, '+9:00')
    assert_equal([2001, 2, 3, 4, 5, 6, Rational(9, 24)],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.commercial(2001, 5, 6, -4, -5, -6, '-9:00')
    assert_equal([2001, 2, 3, 20, 55, 54, Rational(-9, 24)],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
  end

  def test_fractional
    d = Date.jd(2451944.0)
    assert_equal(2451944, d.jd)
    d = Date.jd(Rational(2451944))
    assert_equal(2451944, d.jd)
    d = Date.jd(2451944.5)
    assert_equal(2451944, d.jd)
    d = Date.jd(Rational('2451944.5'))
    assert_equal(2451944, d.jd)

    d = Date.civil(2001, 2, 3.0)
    assert_equal([2001, 2, 3], [d.year, d.mon, d.mday])
    d = Date.civil(2001, 2, Rational(3))
    assert_equal([2001, 2, 3], [d.year, d.mon, d.mday])
    d = Date.civil(2001, 2, 3.5)
    assert_equal([2001, 2, 3], [d.year, d.mon, d.mday])
    d = Date.civil(2001, 2, Rational('3.5'))
    assert_equal([2001, 2, 3], [d.year, d.mon, d.mday])

    d = Date.ordinal(2001, 2.0)
    assert_equal([2001, 2], [d.year, d.yday])
    d = Date.ordinal(2001, Rational(2))
    assert_equal([2001, 2], [d.year, d.yday])

    d = Date.commercial(2001, 2, 3.0)
    assert_equal([2001, 2, 3], [d.cwyear, d.cweek, d.cwday])
    d = Date.commercial(2001, 2, Rational(3))
    assert_equal([2001, 2, 3], [d.cwyear, d.cweek, d.cwday])

    d = DateTime.jd(2451944.0)
    assert_equal(2451944, d.jd)
    d = DateTime.jd(Rational(2451944))
    assert_equal(2451944, d.jd)
    d = DateTime.jd(2451944.5)
    assert_equal([2451944, 12], [d.jd, d.hour])
    d = DateTime.jd(Rational('2451944.5'))
    assert_equal([2451944, 12], [d.jd, d.hour])

    d = DateTime.civil(2001, 2, 3.0)
    assert_equal([2001, 2, 3], [d.year, d.mon, d.mday])
    d = DateTime.civil(2001, 2, Rational(3))
    assert_equal([2001, 2, 3], [d.year, d.mon, d.mday])
    d = DateTime.civil(2001, 2, 3.5)
    assert_equal([2001, 2, 3, 12], [d.year, d.mon, d.mday, d.hour])
    d = DateTime.civil(2001, 2, Rational('3.5'))
    assert_equal([2001, 2, 3, 12], [d.year, d.mon, d.mday, d.hour])
    d = DateTime.civil(2001, 2, 3, 4.5)
    assert_equal([2001, 2, 3, 4, 30], [d.year, d.mon, d.mday, d.hour, d.min])
    d = DateTime.civil(2001, 2, 3, Rational('4.5'))
    assert_equal([2001, 2, 3, 4, 30], [d.year, d.mon, d.mday, d.hour, d.min])
    d = DateTime.civil(2001, 2, 3, 4, 5.5)
    assert_equal([2001, 2, 3, 4, 5, 30],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec])
    d = DateTime.civil(2001, 2, 3, 4, Rational('5.5'))
    assert_equal([2001, 2, 3, 4, 5, 30],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec])

    d = DateTime.ordinal(2001, 2.0)
    assert_equal([2001, 2], [d.year, d.yday])
    d = DateTime.ordinal(2001, Rational(2))
    assert_equal([2001, 2], [d.year, d.yday])

    d = DateTime.commercial(2001, 2, 3.0)
    assert_equal([2001, 2, 3], [d.cwyear, d.cweek, d.cwday])
    d = DateTime.commercial(2001, 2, Rational(3))
    assert_equal([2001, 2, 3], [d.cwyear, d.cweek, d.cwday])

  end

  def test_canon24oc
    d = DateTime.jd(2451943,24)
    assert_equal([2001, 2, 3, 0, 0, 0, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.ordinal(2001,33,24)
    assert_equal([2001, 2, 3, 0, 0, 0, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.new(2001,2,2,24)
    assert_equal([2001, 2, 3, 0, 0, 0, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.commercial(2001,5,5,24)
    assert_equal([2001, 2, 3, 0, 0, 0, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
  end

  def test_zone
    d = DateTime.new(2001, 2, 3)
    assert_equal(Encoding::US_ASCII, d.zone.encoding)
  end

  def test_to_s
    d = Date.new(2001, 2, 3)
    assert_equal(Encoding::US_ASCII, d.to_s.encoding)
    assert_equal(Encoding::US_ASCII, d.strftime.encoding)
    d = DateTime.new(2001, 2, 3)
    assert_equal(Encoding::US_ASCII, d.to_s.encoding)
    assert_equal(Encoding::US_ASCII, d.strftime.encoding)
  end

  def test_inspect
    d = Date.new(2001, 2, 3)
    assert_equal(Encoding::US_ASCII, d.inspect.encoding)
    d = DateTime.new(2001, 2, 3)
    assert_equal(Encoding::US_ASCII, d.inspect.encoding)
  end

  def test_strftime
    assert_raise(Errno::ERANGE) do
      Date.today.strftime('%100000z')
    end
    assert_raise(Errno::ERANGE) do
      Date.new(1 << 10000).strftime('%Y')
    end
    assert_equal('-3786825600', Date.new(1850).strftime('%s'))
    assert_equal('-3786825600000', Date.new(1850).strftime('%Q'))
  end

  def test_cmp
    assert_equal(-1, Date.new(2001,2,3) <=> Date.new(2001,2,4))
    assert_equal(0, Date.new(2001,2,3) <=> Date.new(2001,2,3))
    assert_equal(1, Date.new(2001,2,3) <=> Date.new(2001,2,2))

    assert_equal(-1, Date.new(2001,2,3) <=> 2451944.0)
    assert_equal(-1, Date.new(2001,2,3) <=> 2451944)
    assert_equal(0, Date.new(2001,2,3) <=> 2451943.5)
    assert_equal(1, Date.new(2001,2,3) <=> 2451943.0)
    assert_equal(1, Date.new(2001,2,3) <=> 2451943)

    assert_equal(-1, Date.new(2001,2,3) <=> Rational('4903888/2'))
    assert_equal(0, Date.new(2001,2,3) <=> Rational('4903887/2'))
    assert_equal(1, Date.new(2001,2,3) <=> Rational('4903886/2'))

    assert_equal(-1, Date.new(-4713,11,1,Date::GREGORIAN) <=> Date.new(-4713,12,1,Date::GREGORIAN))
  end

  def test_eqeqeq
    assert_equal(false, Date.new(2001,2,3) === Date.new(2001,2,4))
    assert_equal(true, Date.new(2001,2,3) === Date.new(2001,2,3))
    assert_equal(false, Date.new(2001,2,3) === Date.new(2001,2,2))

    assert_equal(true, Date.new(2001,2,3) === 2451944.0)
    assert_equal(true, Date.new(2001,2,3) === 2451944)
    assert_equal(false, Date.new(2001,2,3) === 2451943.5)
    assert_equal(false, Date.new(2001,2,3) === 2451943.0)
    assert_equal(false, Date.new(2001,2,3) === 2451943)

    assert_equal(true, Date.new(2001,2,3) === Rational('4903888/2'))
    assert_equal(false, Date.new(2001,2,3) === Rational('4903887/2'))
    assert_equal(false, Date.new(2001,2,3) === Rational('4903886/2'))
  end

  def test_period
    # -5000
    d = Date.new(-5000,1,1)
    assert_equal([-5000, 1, 1, 5], [d.year, d.mon, d.mday, d.wday])
    d2 = d.gregorian
    assert_equal([-5001, 11, 22, 5], [d2.year, d2.mon, d2.mday, d.wday])

    d = Date.new(-5000,1,1,Date::JULIAN)
    assert_equal([-5000, 1, 1, 5], [d.year, d.mon, d.mday, d.wday])
    d2 = d.gregorian
    assert_equal([-5001, 11, 22, 5], [d2.year, d2.mon, d2.mday, d.wday])

    d = Date.new(-5000,1,1,Date::GREGORIAN)
    assert_equal([-5000, 1, 1, 3], [d.year, d.mon, d.mday, d.wday])
    d2 = d.julian
    assert_equal([-5000, 2, 10, 3], [d2.year, d2.mon, d2.mday, d.wday])

    d = Date.jd(-105192)
    assert_equal([-5000, 1, 1, 5], [d.year, d.mon, d.mday, d.wday])
    d2 = d.gregorian
    assert_equal([-5001, 11, 22, 5], [d2.year, d2.mon, d2.mday, d.wday])

    d = Date.jd(-105192,Date::JULIAN)
    assert_equal([-5000, 1, 1, 5], [d.year, d.mon, d.mday, d.wday])
    d2 = d.gregorian
    assert_equal([-5001, 11, 22, 5], [d2.year, d2.mon, d2.mday, d.wday])

    d = Date.jd(-105152,Date::GREGORIAN)
    assert_equal([-5000, 1, 1, 3], [d.year, d.mon, d.mday, d.wday])
    d2 = d.julian
    assert_equal([-5000, 2, 10, 3], [d2.year, d2.mon, d2.mday, d.wday])

    # -5000000
    d = Date.new(-5_000_000,1,1)
    assert_equal([-5_000_000, 1, 1, 3], [d.year, d.mon, d.mday, d.wday])
    d2 = d.gregorian
    assert_equal([-5_000_103, 4, 28, 3], [d2.year, d2.mon, d2.mday, d.wday])

    d = Date.new(-5_000_000,1,1,Date::JULIAN)
    assert_equal([-5_000_000, 1, 1, 3], [d.year, d.mon, d.mday, d.wday])
    d2 = d.gregorian
    assert_equal([-5_000_103, 4, 28, 3], [d2.year, d2.mon, d2.mday, d.wday])

    d = Date.new(-5_000_000,1,1,Date::GREGORIAN)
    assert_equal([-5_000_000, 1, 1, 6], [d.year, d.mon, d.mday, d.wday])
    d2 = d.julian
    assert_equal([-4_999_898, 9, 4, 6], [d2.year, d2.mon, d2.mday, d.wday])

    d = Date.jd(-1824528942)
    assert_equal([-5_000_000, 1, 1, 3], [d.year, d.mon, d.mday, d.wday])
    d2 = d.gregorian
    assert_equal([-5_000_103, 4, 28, 3], [d2.year, d2.mon, d2.mday, d.wday])

    d = Date.jd(-1824528942,Date::JULIAN)
    assert_equal([-5_000_000, 1, 1, 3], [d.year, d.mon, d.mday, d.wday])
    d2 = d.gregorian
    assert_equal([-5_000_103, 4, 28, 3], [d2.year, d2.mon, d2.mday, d.wday])

    d = Date.jd(-1824491440,Date::GREGORIAN)
    assert_equal([-5_000_000, 1, 1, 6], [d.year, d.mon, d.mday, d.wday])
    d2 = d.julian
    assert_equal([-4_999_898, 9, 4, 6], [d2.year, d2.mon, d2.mday, d.wday])

    # 5000000
    d = Date.new(5_000_000,1,1)
    assert_equal([5_000_000, 1, 1, 6], [d.year, d.mon, d.mday, d.wday])
    d2 = d.julian
    assert_equal([4_999_897, 5, 3, 6], [d2.year, d2.mon, d2.mday, d.wday])

    d = Date.new(5_000_000,1,1,Date::JULIAN)
    assert_equal([5_000_000, 1, 1, 5], [d.year, d.mon, d.mday, d.wday])
    d2 = d.gregorian
    assert_equal([5_000_102, 9, 1, 5], [d2.year, d2.mon, d2.mday, d.wday])

    d = Date.new(5_000_000,1,1,Date::GREGORIAN)
    assert_equal([5_000_000, 1, 1, 6], [d.year, d.mon, d.mday, d.wday])
    d2 = d.julian
    assert_equal([4_999_897, 5, 3, 6], [d2.year, d2.mon, d2.mday, d.wday])

    d = Date.jd(1827933560)
    assert_equal([5_000_000, 1, 1, 6], [d.year, d.mon, d.mday, d.wday])
    d2 = d.julian
    assert_equal([4_999_897, 5, 3, 6], [d2.year, d2.mon, d2.mday, d.wday])

    d = Date.jd(1827971058,Date::JULIAN)
    assert_equal([5_000_000, 1, 1, 5], [d.year, d.mon, d.mday, d.wday])
    d2 = d.gregorian
    assert_equal([5_000_102, 9, 1, 5], [d2.year, d2.mon, d2.mday, d.wday])

    d = Date.jd(1827933560,Date::GREGORIAN)
    assert_equal([5_000_000, 1, 1, 6], [d.year, d.mon, d.mday, d.wday])
    d2 = d.julian
    assert_equal([4_999_897, 5, 3, 6], [d2.year, d2.mon, d2.mday, d.wday])

    # dt
    d = DateTime.new(-123456789,2,3,4,5,6,0)
    assert_equal([-123456789, 2, 3, 4, 5, 6, 1],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.wday])
    d2 = d.gregorian
    assert_equal([-123459325, 12, 27, 4, 5, 6, 1],
		 [d2.year, d2.mon, d2.mday, d2.hour, d2.min, d2.sec, d.wday])

    d = DateTime.new(123456789,2,3,4,5,6,0)
    assert_equal([123456789, 2, 3, 4, 5, 6, 5],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.wday])
    d2 = d.julian
    assert_equal([123454254, 1, 19, 4, 5, 6, 5],
		 [d2.year, d2.mon, d2.mday, d2.hour, d2.min, d2.sec, d.wday])
  end

  def period2_iter2(from, to, sg)
    (from..to).each do |j|
      d = Date.jd(j, sg)
      d2 = Date.new(d.year, d.mon, d.mday, sg)
      assert_equal(d2.jd, j)
      assert_equal(d2.ajd, d.ajd)
      assert_equal(d2.year, d.year)

      d = DateTime.jd(j, 12,0,0, '+12:00', sg)
      d2 = DateTime.new(d.year, d.mon, d.mday,
			d.hour, d.min, d.sec, d.offset, sg)
      assert_equal(d2.jd, j)
      assert_equal(d2.ajd, d.ajd)
      assert_equal(d2.year, d.year)
    end
  end

  def period2_iter(from, to)
    period2_iter2(from, to, Date::GREGORIAN)
    period2_iter2(from, to, Date::ITALY)
    period2_iter2(from, to, Date::ENGLAND)
    period2_iter2(from, to, Date::JULIAN)
  end

  def test_period2
    cm_period0 = 71149239
    cm_period = 0xfffffff.div(cm_period0) * cm_period0
    period2_iter(-cm_period * (1 << 64) - 3, -cm_period * (1 << 64) + 3)
    period2_iter(-cm_period - 3, -cm_period + 3)
    period2_iter(0 - 3, 0 + 3)
    period2_iter(+cm_period - 3, +cm_period + 3)
    period2_iter(+cm_period * (1 << 64) - 3, +cm_period * (1 << 64) + 3)
  end

  def test_different_alignments
    assert_equal(0, Date.jd(0) <=> Date.civil(-4713, 11, 24, Date::GREGORIAN))
    assert_equal(0, Date.jd(213447717) <=> Date.civil(579687, 11, 24))
    assert_equal(0, Date.jd(-213447717) <=> Date.civil(-589113, 11, 24, Date::GREGORIAN))

    assert_equal(0, Date.jd(0) <=> DateTime.civil(-4713, 11, 24, 0, 0, 0, 0, Date::GREGORIAN))
    assert_equal(0, Date.jd(213447717) <=> DateTime.civil(579687, 11, 24))
    assert_equal(0, Date.jd(-213447717) <=> DateTime.civil(-589113, 11, 24, 0, 0, 0, 0, Date::GREGORIAN))

    assert(Date.jd(0) == Date.civil(-4713, 11, 24, Date::GREGORIAN))
    assert(Date.jd(213447717) == Date.civil(579687, 11, 24))
    assert(Date.jd(-213447717) == Date.civil(-589113, 11, 24, Date::GREGORIAN))

    assert(Date.jd(0) == DateTime.civil(-4713, 11, 24, 0, 0, 0, 0, Date::GREGORIAN))
    assert(Date.jd(213447717) == DateTime.civil(579687, 11, 24))
    assert(Date.jd(-213447717) == DateTime.civil(-589113, 11, 24, 0, 0, 0, 0, Date::GREGORIAN))

    assert(Date.jd(0) === Date.civil(-4713, 11, 24, Date::GREGORIAN))
    assert(Date.jd(213447717) === Date.civil(579687, 11, 24))
    assert(Date.jd(-213447717) === Date.civil(-589113, 11, 24, Date::GREGORIAN))

    assert(Date.jd(0) === DateTime.civil(-4713, 11, 24, 12, 0, 0, 0, Date::GREGORIAN))
    assert(Date.jd(213447717) === DateTime.civil(579687, 11, 24, 12))
    assert(Date.jd(-213447717) === DateTime.civil(-589113, 11, 24, 12, 0, 0, 0, Date::GREGORIAN))

    a = Date.jd(0)
    b = Date.civil(-4713, 11, 24, Date::GREGORIAN)
    assert_equal(0, a <=> b)

    a = Date.civil(-4712, 1, 1, Date::JULIAN)
    b = Date.civil(-4713, 11, 24, Date::GREGORIAN)
    a.jd; b.jd
    assert_equal(0, a <=> b)

    a = Date.jd(0)
    b = Date.civil(-4713, 11, 24, Date::GREGORIAN)
    assert(a == b)

    a = Date.civil(-4712, 1, 1, Date::JULIAN)
    b = Date.civil(-4713, 11, 24, Date::GREGORIAN)
    a.jd; b.jd
    assert(a == b)

    a = Date.jd(0)
    b = Date.civil(-4713, 11, 24, Date::GREGORIAN)
    assert(a === b)

    a = Date.civil(-4712, 1, 1, Date::JULIAN)
    b = Date.civil(-4713, 11, 24, Date::GREGORIAN)
    a.jd; b.jd
    assert(a === b)
  end

  def test_marshal14
    s = "\x04\x03u:\x01\x04Date\x01\v\x04\x03[\x01\x02i\x03\xE8i%T"
    d = Marshal.load(s)
    assert_equal(Rational(4903887,2), d.ajd)
    assert_equal(Date::GREGORIAN, d.start)
  end

  def test_marshal16
    s = "\x04\x06u:\tDate\x0F\x04\x06[\ai\x03\xE8i%T"
    d = Marshal.load(s)
    assert_equal(Rational(4903887,2), d.ajd)
    assert_equal(Date::GREGORIAN, d.start)
  end

  def test_marshal18
    s = "\x04\bu:\tDateP\x04\b[\bo:\rRational\a:\x0F@numeratori\x03\xCF\xD3J:\x11@denominatori\ai\x00o:\x13Date::Infinity\x06:\a@di\xFA"
    d = Marshal.load(s)
    assert_equal(Rational(4903887,2), d.ajd)
    assert_equal(Date::GREGORIAN, d.start)

    s = "\x04\bu:\rDateTime`\x04\b[\bo:\rRational\a:\x0F@numeratorl+\b\xC9\xB0\x81\xBD\x02\x00:\x11@denominatori\x02\xC0\x12o;\x00\a;\x06i\b;\ai\ro:\x13Date::Infinity\x06:\a@di\xFA"
    d = Marshal.load(s)
    assert_equal(Rational(11769327817,4800), d.ajd)
    assert_equal(Rational(9,24), d.offset)
    assert_equal(Date::GREGORIAN, d.start)
  end

  def test_marshal192
    s = "\x04\bU:\tDate[\bU:\rRational[\ai\x03\xCF\xD3Ji\ai\x00o:\x13Date::Infinity\x06:\a@di\xFA"
    d = Marshal.load(s)
    assert_equal(Rational(4903887,2), d.ajd)
    assert_equal(Date::GREGORIAN, d.start)

    s = "\x04\bU:\rDateTime[\bU:\rRational[\al+\b\xC9\xB0\x81\xBD\x02\x00i\x02\xC0\x12U;\x06[\ai\bi\ro:\x13Date::Infinity\x06:\a@di\xFA"
    d = Marshal.load(s)
    assert_equal(Rational(11769327817,4800), d.ajd)
    assert_equal(Rational(9,24), d.offset)
    assert_equal(Date::GREGORIAN, d.start)
  end

  def test_taint
    h = Date._strptime('15:43+09:00', '%R%z')
    assert_equal(false, h[:zone].tainted?)
    h = Date._strptime('15:43+09:00'.dup.taint, '%R%z')
    assert_equal(true, h[:zone].tainted?)

    h = Date._strptime('1;1/0', '%d')
    assert_equal(false, h[:leftover].tainted?)
    h = Date._strptime('1;1/0'.dup.taint, '%d')
    assert_equal(true, h[:leftover].tainted?)

    h = Date._parse('15:43+09:00')
    assert_equal(false, h[:zone].tainted?)
    h = Date._parse('15:43+09:00'.dup.taint)
    assert_equal(true, h[:zone].tainted?)

    s = Date.today.strftime('new 105')
    assert_equal(false, s.tainted?)
    s = Date.today.strftime('new 105'.dup.taint)
    assert_equal(true, s.tainted?)
    s = Date.today.strftime("new \000 105".dup.taint)
    assert_equal(true, s.tainted?)

    s = DateTime.now.strftime('super $record')
    assert_equal(false, s.tainted?)
    s = DateTime.now.strftime('super $record'.dup.taint)
    assert_equal(true, s.tainted?)
  end

  def test_enc
    Date::MONTHNAMES.each do |s|
      assert_equal(Encoding::US_ASCII, s.encoding) if s
    end
    Date::DAYNAMES.each do |s|
      assert_equal(Encoding::US_ASCII, s.encoding) if s
    end
    Date::ABBR_MONTHNAMES.each do |s|
      assert_equal(Encoding::US_ASCII, s.encoding) if s
    end
    Date::ABBR_DAYNAMES.each do |s|
      assert_equal(Encoding::US_ASCII, s.encoding) if s
    end

    h = Date._strptime('15:43+09:00'.dup.force_encoding('euc-jp'), '%R%z')
    assert_equal(Encoding::EUC_JP, h[:zone].encoding)
    h = Date._strptime('15:43+09:00'.dup.force_encoding('ascii-8bit'), '%R%z')
    assert_equal(Encoding::ASCII_8BIT, h[:zone].encoding)

    h = Date._strptime('1;1/0'.dup.force_encoding('euc-jp'), '%d')
    assert_equal(Encoding::EUC_JP, h[:leftover].encoding)
    h = Date._strptime('1;1/0'.dup.force_encoding('ascii-8bit'), '%d')
    assert_equal(Encoding::ASCII_8BIT, h[:leftover].encoding)

    h = Date._parse('15:43+09:00'.dup.force_encoding('euc-jp'))
    assert_equal(Encoding::EUC_JP, h[:zone].encoding)
    h = Date._parse('15:43+09:00'.dup.force_encoding('ascii-8bit'))
    assert_equal(Encoding::ASCII_8BIT, h[:zone].encoding)

    s = Date.today.strftime('new 105'.dup.force_encoding('euc-jp'))
    assert_equal(Encoding::EUC_JP, s.encoding)
    s = Date.today.strftime('new 105'.dup.force_encoding('ascii-8bit'))
    assert_equal(Encoding::ASCII_8BIT, s.encoding)

    s = DateTime.now.strftime('super $record'.dup.force_encoding('euc-jp'))
    assert_equal(Encoding::EUC_JP, s.encoding)
    s = DateTime.now.strftime('super $record'.dup.force_encoding('ascii-8bit'))
    assert_equal(Encoding::ASCII_8BIT, s.encoding)
  end

  def test_dup
    d = Date.new(2001,2,3)
    d2 = d.dup
    assert_not_equal(d.object_id, d2.object_id)
    assert_kind_of(Date, d2)
    assert_equal(d, d2)

    d = DateTime.new(2001,2,3)
    d2 = d.dup
    assert_not_equal(d.object_id, d2.object_id)
    assert_kind_of(DateTime, d2)
    assert_equal(d, d2)
  end

  def test_base
    assert_equal(true, Date.test_all)
  end if defined?(Date.test_all)

end
