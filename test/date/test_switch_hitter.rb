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

  def test_zone
    d = Date.new(2001, 2, 3)
    assert_equal(Encoding::US_ASCII, d.send(:zone).encoding)
    d = DateTime.new(2001, 2, 3)
    assert_equal(Encoding::US_ASCII, d.send(:zone).encoding)
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

  def test_marshal
    s = "\x04\bU:\tDate[\bU:\rRational[\ai\x03\xCF\xD3Ji\ai\x00o:\x13Date::Infinity\x06:\a@di\xFA"
    d = Marshal.load(s)
    assert_equal(Date.new(2001,2,3,Date::GREGORIAN), d)

    s = "\x04\bU:\rDateTime[\bU:\rRational[\al+\b\xC9\xB0\x81\xBD\x02\x00i\x02\xC0\x12U;\x06[\ai\bi\ro:\x13Date::Infinity\x06:\a@di\xFA"
    d = Marshal.load(s)
    assert_equal(DateTime.new(2001,2,3,4,5,6,Rational(9,24),Date::GREGORIAN), d)
  end

  def test_base
    skip unless defined?(Date.test_all)
    assert_equal(true, Date.test_all)
  end

  def test_taint
    h = Date._strptime('15:43+09:00', '%R%z')
    assert_equal(false, h[:zone].tainted?)
    h = Date._strptime('15:43+09:00'.taint, '%R%z')
    assert_equal(true, h[:zone].tainted?)

    h = Date._parse('15:43+09:00')
    assert_equal(false, h[:zone].tainted?)
    h = Date._parse('15:43+09:00'.taint)
    assert_equal(true, h[:zone].tainted?)

    s = Date.today.strftime('new 105')
    assert_equal(false, s.tainted?)
    s = Date.today.strftime('new 105'.taint)
    assert_equal(true, s.tainted?)

    s = DateTime.now.strftime('super $record')
    assert_equal(false, s.tainted?)
    s = DateTime.now.strftime('super $record'.taint)
    assert_equal(true, s.tainted?)
  end

end
