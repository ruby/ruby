require 'test/unit'
require 'xsd/datatypes'


module XSD


class TestXSD < Test::Unit::TestCase
  NegativeZero = (-1.0 / (1.0 / 0.0))

  def setup
  end

  def teardown
  end

  def assert_parsed_result(klass, str)
    o = klass.new(str)
    assert_equal(str, o.to_s)
  end

  def test_NSDBase
    o = XSD::NSDBase.new
    assert_equal(nil, o.type)
  end

  def test_XSDBase
    o = XSD::XSDAnySimpleType.new
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)
    assert_equal('', o.to_s)
  end

  def test_XSDNil
    o = XSD::XSDNil.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::NilLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    o = XSD::XSDNil.new(nil)
    assert_equal(true, o.is_nil)
    assert_equal(nil, o.data)
    assert_equal("", o.to_s)
    o = XSD::XSDNil.new('var')
    assert_equal(false, o.is_nil)
    assert_equal('var', o.data)
    assert_equal('var', o.to_s)
  end

  def test_XSDString_UTF8
    o = XSD::XSDString.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::StringLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    str = "abc"
    assert_equal(str, XSD::XSDString.new(str).data)
    assert_equal(str, XSD::XSDString.new(str).to_s)
    assert_raises(XSD::ValueSpaceError) do
      XSD::XSDString.new("\0")
    end
    assert_raises(XSD::ValueSpaceError) do
      p XSD::XSDString.new("\xC0\xC0").to_s
    end
  end

  def test_XSDString_NONE
    XSD::Charset.module_eval { @encoding_backup = @encoding; @encoding = "NONE" }
    begin
      o = XSD::XSDString.new
      assert_equal(XSD::Namespace, o.type.namespace)
      assert_equal(XSD::StringLiteral, o.type.name)
      assert_equal(nil, o.data)
      assert_equal(true, o.is_nil)

      str = "abc"
      assert_equal(str, XSD::XSDString.new(str).data)
      assert_equal(str, XSD::XSDString.new(str).to_s)
      assert_raises(XSD::ValueSpaceError) do
	XSD::XSDString.new("\0")
      end
      assert_raises(XSD::ValueSpaceError) do
	p XSD::XSDString.new("\xC0\xC0").to_s
      end
    ensure
      XSD::Charset.module_eval { @encoding = @encoding_backup }
    end
  end

  def test_XSDBoolean
    o = XSD::XSDBoolean.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::BooleanLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      ["true", true],
      ["1", true],
      ["false", false],
      ["0", false],
    ]
    targets.each do |data, expected|
      assert_equal(expected, XSD::XSDBoolean.new(data).data)
      assert_equal(expected.to_s, XSD::XSDBoolean.new(data).to_s)
    end

    assert_raises(XSD::ValueSpaceError) do
      XSD::XSDBoolean.new("nil").to_s
    end
  end

  def test_XSDDecimal
    o = XSD::XSDDecimal.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::DecimalLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      0,
      1000000000,
      -9999999999,
      12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890,
      12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890,
      -1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789,
    ]
    targets.each do |dec|
      assert_equal(dec.to_s, XSD::XSDDecimal.new(dec).data)
    end

    targets = [
      "0",
      "0.00000001",
      "1000000000",
      "12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890",
      "-12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123.45678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789",
    ]
    targets.each do |str|
      assert_equal(str, XSD::XSDDecimal.new(str).to_s)
    end

    targets = [
      ["-0", "0"],
      ["+0", "0"],
      ["0.0", "0"],
      ["-0.0", "0"],
      ["+0.0", "0"],
      ["0.", "0"],
      [".0", "0"],
      [
	"+0.12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890",
	"0.1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789"
     ],
      [
	".0000012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890",
	"0.000001234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789"
     ],
      [
	"-12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890.",
	"-12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890"
     ],
    ]
    targets.each do |data, expected|
      assert_equal(expected, XSD::XSDDecimal.new(data).to_s)
    end

    targets = [
      "0.000000000000a",
      "00a.0000000000001",
      "+-5",
    ]
    targets.each do |d|
      assert_raises(XSD::ValueSpaceError) do
	XSD::XSDDecimal.new(d)
      end
    end
  end

  def test_XSDFloat
    o = XSD::XSDFloat.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::FloatLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      3.14159265358979,
      12.34e36,
      1.4e-45,
      -1.4e-45,
    ]
    targets.each do |f|
      assert_equal(f, XSD::XSDFloat.new(f).data)
    end

    targets = [
      "+3.141592654",
      "+1.234e+37",
      "+1.4e-45",
      "-1.4e-45",
    ]
    targets.each do |f|
      assert_equal(f, XSD::XSDFloat.new(f).to_s)
    end

    targets = [
      [3, "+3"], 	# should be 3.0?
      [-2, "-2"],	# ditto
      [3.14159265358979, "+3.141592654"],
      [12.34e36, "+1.234e+37"],
      [1.4e-45, "+1.4e-45"],
      [-1.4e-45, "-1.4e-45"],
      ["1.4e", "+1.4"],
      ["12.34E36", "+1.234e+37"],
      ["1.4E-45", "+1.4e-45"],
      ["-1.4E-45", "-1.4e-45"],
      ["1.4E", "+1.4"],
    ]
    targets.each do |f, str|
      assert_equal(str, XSD::XSDFloat.new(f).to_s)
    end

    assert_equal("+0", XSD::XSDFloat.new(+0.0).to_s)
    assert_equal("-0", XSD::XSDFloat.new(NegativeZero).to_s)
    assert(XSD::XSDFloat.new(0.0/0.0).data.nan?)
    assert_equal("INF", XSD::XSDFloat.new(1.0/0.0).to_s)
    assert_equal(1, XSD::XSDFloat.new(1.0/0.0).data.infinite?)
    assert_equal("-INF", XSD::XSDFloat.new(-1.0/0.0).to_s)
    assert_equal(-1, XSD::XSDFloat.new(-1.0/0.0).data.infinite?)

    targets = [
      "0.000000000000a",
      "00a.0000000000001",
      "+-5",
      "5_0",
    ]
    targets.each do |d|
      assert_raises(XSD::ValueSpaceError) do
	XSD::XSDFloat.new(d)
      end
    end
  end

  def test_XSDDouble
    o = XSD::XSDDouble.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::DoubleLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      3.14159265358979,
      12.34e36,
      1.4e-45,
      -1.4e-45,
    ]
    targets.each do |f|
      assert_equal(f, XSD::XSDDouble.new(f).data)
    end

    targets = [
      "+3.14159265358979",
      "+1.234e+37",
      "+1.4e-45",
      "-1.4e-45",
    ]
    targets.each do |f|
      assert_equal(f, XSD::XSDDouble.new(f).to_s)
    end

    targets = [
      [3, "+3"],	# should be 3.0?
      [-2, "-2"],	# ditto.
      [3.14159265358979, "+3.14159265358979"],
      [12.34e36, "+1.234e+37"],
      [1.4e-45, "+1.4e-45"],
      [-1.4e-45, "-1.4e-45"],
      ["1.4e", "+1.4"],
      ["12.34E36", "+1.234e+37"],
      ["1.4E-45", "+1.4e-45"],
      ["-1.4E-45", "-1.4e-45"],
      ["1.4E", "+1.4"],
    ]
    targets.each do |f, str|
      assert_equal(str, XSD::XSDDouble.new(f).to_s)
    end

    assert_equal("+0", XSD::XSDFloat.new(+0.0).to_s)
    assert_equal("-0", XSD::XSDFloat.new(NegativeZero).to_s)
    assert_equal("NaN", XSD::XSDDouble.new(0.0/0.0).to_s)
    assert(XSD::XSDDouble.new(0.0/0.0).data.nan?)
    assert_equal("INF", XSD::XSDDouble.new(1.0/0.0).to_s)
    assert_equal(1, XSD::XSDDouble.new(1.0/0.0).data.infinite?)
    assert_equal("-INF", XSD::XSDDouble.new(-1.0/0.0).to_s)
    assert_equal(-1, XSD::XSDDouble.new(-1.0/0.0).data.infinite?)

    targets = [
      "0.000000000000a",
      "00a.0000000000001",
      "+-5",
    ]
    targets.each do |d|
      assert_raises(XSD::ValueSpaceError) do
	XSD::XSDDouble.new(d)
      end
    end
  end

  def test_XSDDuration
    o = XSD::XSDDuration.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::DurationLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      "P1Y2M3DT4H5M6S",
      "P1234Y5678M9012DT3456H7890M1234.5678S",
      "P0DT3456H7890M1234.5678S",
      "P1234Y5678M9012D",
      "-P1234Y5678M9012DT3456H7890M1234.5678S",
      "P5678M9012DT3456H7890M1234.5678S",
      "-P1234Y9012DT3456H7890M1234.5678S",
      "+P1234Y5678MT3456H7890M1234.5678S",
      "P1234Y5678M9012DT7890M1234.5678S",
      "-P1234Y5678M9012DT3456H1234.5678S",
      "+P1234Y5678M9012DT3456H7890M",
      "P123400000000000Y",
      "-P567800000000000M",
      "+P901200000000000D",
      "P0DT345600000000000H",
      "-P0DT789000000000000M",
      "+P0DT123400000000000.000000000005678S",
      "P1234YT1234.5678S",
      "-P5678MT7890M",
      "+P9012DT3456H",
    ]
    targets.each do |str|
      assert_parsed_result(XSD::XSDDuration, str)
    end

    targets = [
      ["P0Y0M0DT0H0M0S",
        "P0D"],
      ["-P0DT0S",
        "-P0D"],
      ["P01234Y5678M9012DT3456H7890M1234.5678S",
        "P1234Y5678M9012DT3456H7890M1234.5678S"],
      ["P1234Y005678M9012DT3456H7890M1234.5678S",
        "P1234Y5678M9012DT3456H7890M1234.5678S"],
      ["P1234Y5678M0009012DT3456H7890M1234.5678S",
        "P1234Y5678M9012DT3456H7890M1234.5678S"],
      ["P1234Y5678M9012DT00003456H7890M1234.5678S",
        "P1234Y5678M9012DT3456H7890M1234.5678S"],
      ["P1234Y5678M9012DT3456H000007890M1234.5678S",
        "P1234Y5678M9012DT3456H7890M1234.5678S"],
      ["P1234Y5678M9012DT3456H7890M0000001234.5678S",
        "P1234Y5678M9012DT3456H7890M1234.5678S"],
    ]
    targets.each do |data, expected|
      assert_equal(expected, XSD::XSDDuration.new(data).to_s)
    end
  end

  def test_XSDDateTime
    o = XSD::XSDDateTime.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::DateTimeLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      "2002-05-18T16:52:20Z",
      "0001-01-01T00:00:00Z",
      "9999-12-31T23:59:59Z",
      "19999-12-31T23:59:59Z",
      "2002-12-31T23:59:59.999Z",
      "2002-12-31T23:59:59.001Z",
      "2002-12-31T23:59:59.99999999999999999999Z",
      "2002-12-31T23:59:59.00000000000000000001Z",
      "2002-12-31T23:59:59+09:00",
      "2002-12-31T23:59:59+00:01",
      "2002-12-31T23:59:59-00:01",
      "2002-12-31T23:59:59-23:59",
      "2002-12-31T23:59:59.00000000000000000001+13:30",
      "2002-12-31T23:59:59.5137Z",
      "2002-12-31T23:59:59.51375Z",	# 411/800
      "2002-12-31T23:59:59.51375+12:34",
      "-2002-05-18T16:52:20Z",
      "-4713-01-01T12:00:00Z",
      "-2002-12-31T23:59:59+00:01",
      "-0001-12-31T23:59:59.00000000000000000001+13:30",
    ]
    targets.each do |str|
      assert_parsed_result(XSD::XSDDateTime, str)
    end

    targets = [
      ["2002-12-31T23:59:59.00",
	"2002-12-31T23:59:59Z"],
      ["2002-12-31T23:59:59+00:00",
	"2002-12-31T23:59:59Z"],
      ["2002-12-31T23:59:59-00:00",
	"2002-12-31T23:59:59Z"],
      ["-2002-12-31T23:59:59.00",
	"-2002-12-31T23:59:59Z"],
      ["-2002-12-31T23:59:59+00:00",
	"-2002-12-31T23:59:59Z"],
      ["-2002-12-31T23:59:59-00:00",
	"-2002-12-31T23:59:59Z"],
    ]
    targets.each do |data, expected|
      assert_equal(expected, XSD::XSDDateTime.new(data).to_s)
    end

    targets = [
      "0000-05-18T16:52:20Z",
      "05-18T16:52:20Z",
      "2002-05T16:52:20Z",
      "2002-05-18T16:52Z",
      "",
    ]
    targets.each do |d|
      assert_raises(XSD::ValueSpaceError, d.to_s) do
	XSD::XSDDateTime.new(d)
      end
    end
  end

  def test_XSDTime
    o = XSD::XSDTime.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::TimeLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      "16:52:20Z",
      "00:00:00Z",
      "23:59:59Z",
      "23:59:59.999Z",
      "23:59:59.001Z",
      "23:59:59.99999999999999999999Z",
      "23:59:59.00000000000000000001Z",
      "23:59:59+09:00",
      "23:59:59+00:01",
      "23:59:59-00:01",
      "23:59:59-23:59",
      "23:59:59.00000000000000000001+13:30",
      "23:59:59.51345Z",
      "23:59:59.51345+12:34",
      "23:59:59+00:01",
    ]
    targets.each do |str|
      assert_parsed_result(XSD::XSDTime, str)
    end

    targets = [
      ["23:59:59.00",
	"23:59:59Z"],
      ["23:59:59+00:00",
	"23:59:59Z"],
      ["23:59:59-00:00",
	"23:59:59Z"],
    ]
    targets.each do |data, expected|
      assert_equal(expected, XSD::XSDTime.new(data).to_s)
    end
  end

  def test_XSDDate
    o = XSD::XSDDate.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::DateLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      "2002-05-18Z",
      "0001-01-01Z",
      "9999-12-31Z",
      "19999-12-31Z",
      "2002-12-31+09:00",
      "2002-12-31+00:01",
      "2002-12-31-00:01",
      "2002-12-31-23:59",
      "2002-12-31+13:30",
      "-2002-05-18Z",
      "-19999-12-31Z",
      "-2002-12-31+00:01",
      "-0001-12-31+13:30",
    ]
    targets.each do |str|
      assert_parsed_result(XSD::XSDDate, str)
    end

    targets = [
      ["2002-12-31",
	"2002-12-31Z"],
      ["2002-12-31+00:00",
	"2002-12-31Z"],
      ["2002-12-31-00:00",
	"2002-12-31Z"],
      ["-2002-12-31",
	"-2002-12-31Z"],
      ["-2002-12-31+00:00",
	"-2002-12-31Z"],
      ["-2002-12-31-00:00",
	"-2002-12-31Z"],
    ]
    targets.each do |data, expected|
      assert_equal(expected, XSD::XSDDate.new(data).to_s)
    end
  end
end

class TestXSD2 < Test::Unit::TestCase
  def setup
    # Nothing to do.
  end

  def teardown
    # Nothing to do.
  end

  def assert_parsed_result(klass, str)
    o = klass.new(str)
    assert_equal(str, o.to_s)
  end

  def test_XSDGYearMonth
    o = XSD::XSDGYearMonth.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::GYearMonthLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      "2002-05Z",
      "0001-01Z",
      "9999-12Z",
      "19999-12Z",
      "2002-12+09:00",
      "2002-12+00:01",
      "2002-12-00:01",
      "2002-12-23:59",
      "2002-12+13:30",
      "-2002-05Z",
      "-19999-12Z",
      "-2002-12+00:01",
      "-0001-12+13:30",
    ]
    targets.each do |str|
      assert_parsed_result(XSD::XSDGYearMonth, str)
    end

    targets = [
      ["2002-12",
	"2002-12Z"],
      ["2002-12+00:00",
	"2002-12Z"],
      ["2002-12-00:00",
	"2002-12Z"],
      ["-2002-12",
	"-2002-12Z"],
      ["-2002-12+00:00",
	"-2002-12Z"],
      ["-2002-12-00:00",
	"-2002-12Z"],
    ]
    targets.each do |data, expected|
      assert_equal(expected, XSD::XSDGYearMonth.new(data).to_s)
    end
  end

  def test_XSDGYear
    o = XSD::XSDGYear.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::GYearLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      "2002Z",
      "0001Z",
      "9999Z",
      "19999Z",
      "2002+09:00",
      "2002+00:01",
      "2002-00:01",
      "2002-23:59",
      "2002+13:30",
      "-2002Z",
      "-19999Z",
      "-2002+00:01",
      "-0001+13:30",
    ]
    targets.each do |str|
      assert_parsed_result(XSD::XSDGYear, str)
    end

    targets = [
      ["2002",
	"2002Z"],
      ["2002+00:00",
	"2002Z"],
      ["2002-00:00",
	"2002Z"],
      ["-2002",
	"-2002Z"],
      ["-2002+00:00",
	"-2002Z"],
      ["-2002-00:00",
	"-2002Z"],
    ]
    targets.each do |data, expected|
      assert_equal(expected, XSD::XSDGYear.new(data).to_s)
    end
  end

  def test_XSDGMonthDay
    o = XSD::XSDGMonthDay.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::GMonthDayLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      "05-18Z",
      "01-01Z",
      "12-31Z",
      "12-31+09:00",
      "12-31+00:01",
      "12-31-00:01",
      "12-31-23:59",
      "12-31+13:30",
    ]
    targets.each do |str|
      assert_parsed_result(XSD::XSDGMonthDay, str)
    end

    targets = [
      ["12-31",
	"12-31Z"],
      ["12-31+00:00",
	"12-31Z"],
      ["12-31-00:00",
	"12-31Z"],
    ]
    targets.each do |data, expected|
      assert_equal(expected, XSD::XSDGMonthDay.new(data).to_s)
    end
  end

  def test_XSDGDay
    o = XSD::XSDGDay.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::GDayLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      "18Z",
      "01Z",
      "31Z",
      "31+09:00",
      "31+00:01",
      "31-00:01",
      "31-23:59",
      "31+13:30",
    ]
    targets.each do |str|
      assert_parsed_result(XSD::XSDGDay, str)
    end

    targets = [
      ["31",
	"31Z"],
      ["31+00:00",
	"31Z"],
      ["31-00:00",
	"31Z"],
    ]
    targets.each do |data, expected|
      assert_equal(expected, XSD::XSDGDay.new(data).to_s)
    end
  end

  def test_XSDGMonth
    o = XSD::XSDGMonth.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::GMonthLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      "05Z",
      "01Z",
      "12Z",
      "12+09:00",
      "12+00:01",
      "12-00:01",
      "12-23:59",
      "12+13:30",
    ]
    targets.each do |str|
      assert_parsed_result(XSD::XSDGMonth, str)
    end

    targets = [
      ["12",
	"12Z"],
      ["12+00:00",
	"12Z"],
      ["12-00:00",
	"12Z"],
    ]
    targets.each do |data, expected|
      assert_equal(expected, XSD::XSDGMonth.new(data).to_s)
    end
  end

  def test_XSDHexBinary
    o = XSD::XSDHexBinary.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::HexBinaryLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      "abcdef",
      "\xe3\x81\xaa\xe3\x81\xb2",
      %Q(\0),
      "",
    ]
    targets.each do |str|
      assert_equal(str, XSD::XSDHexBinary.new(str).string)
      assert_equal(str.unpack("H*")[0 ].tr('a-f', 'A-F'),
	XSD::XSDHexBinary.new(str).data)
      o = XSD::XSDHexBinary.new
      o.set_encoded(str.unpack("H*")[0 ].tr('a-f', 'A-F'))
      assert_equal(str, o.string)
      o.set_encoded(str.unpack("H*")[0 ].tr('A-F', 'a-f'))
      assert_equal(str, o.string)
    end

    targets = [
      "0FG7",
      "0fg7",
    ]
    targets.each do |d|
      assert_raises(XSD::ValueSpaceError, d.to_s) do
	o = XSD::XSDHexBinary.new
	o.set_encoded(d)
	p o.string
      end
    end
  end

  def test_XSDBase64Binary
    o = XSD::XSDBase64Binary.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::Base64BinaryLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      "abcdef",
      "\xe3\x81\xaa\xe3\x81\xb2",
      %Q(\0),
      "",
    ]
    targets.each do |str|
      assert_equal(str, XSD::XSDBase64Binary.new(str).string)
      assert_equal([str ].pack("m").chomp, XSD::XSDBase64Binary.new(str).data)
      o = XSD::XSDBase64Binary.new
      o.set_encoded([str ].pack("m").chomp)
      assert_equal(str, o.string)
    end

    targets = [
      "-",
      "*",
    ]
    targets.each do |d|
      assert_raises(XSD::ValueSpaceError, d.to_s) do
	o = XSD::XSDBase64Binary.new
	o.set_encoded(d)
	p o.string
      end
    end
  end

  def test_XSDAnyURI
    o = XSD::XSDAnyURI.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::AnyURILiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    # Too few tests here I know.  Believe uri module. :)
    targets = [
      "foo",
      "http://foo",
      "http://foo/bar/baz",
      "http://foo/bar#baz",
      "http://foo/bar%20%20?a+b",
      "HTTP://FOO/BAR%20%20?A+B",
    ]
    targets.each do |str|
      assert_parsed_result(XSD::XSDAnyURI, str)
    end
  end

  def test_XSDQName
    o = XSD::XSDQName.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::QNameLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    # More strict test is needed but current implementation allows all non-':'
    # chars like ' ', C0 or C1...
    targets = [
      "foo",
      "foo:bar",
      "a:b",
    ]
    targets.each do |str|
      assert_parsed_result(XSD::XSDQName, str)
    end
  end


  ###
  ## Derived types
  #

  def test_XSDInteger
    o = XSD::XSDInteger.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::IntegerLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      0,
      1000000000,
      -9999999999,
      12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890,
      12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890,
      -1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789,
    ]
    targets.each do |int|
      assert_equal(int, XSD::XSDInteger.new(int).data)
    end

    targets = [
      "0",
      "1000000000",
      "-9999999999",
      "12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890",
      "12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890",
      "-1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789",
    ]
    targets.each do |str|
      assert_equal(str, XSD::XSDInteger.new(str).to_s)
    end

    targets = [
      ["-0", "0"],
      ["+0", "0"],
      ["000123", "123"],
      ["-000123", "-123"],
      [
	"+12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890",
	"12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890"
     ],
    ]
    targets.each do |data, expected|
      assert_equal(expected, XSD::XSDInteger.new(data).to_s)
    end

    targets = [
      "0.0",
      "-5.2",
      "0.000000000000a",
      "+-5",
      "12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890."
    ]
    targets.each do |d|
      assert_raises(XSD::ValueSpaceError) do
	XSD::XSDInteger.new(d)
      end
    end
  end

  def test_XSDLong
    o = XSD::XSDLong.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::LongLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      0,
      123,
      -123,
      9223372036854775807,
      -9223372036854775808,
    ]
    targets.each do |lng|
      assert_equal(lng, XSD::XSDLong.new(lng).data)
    end

    targets = [
      "0",
      "123",
      "-123",
      "9223372036854775807",
      "-9223372036854775808",
    ]
    targets.each do |str|
      assert_equal(str, XSD::XSDLong.new(str).to_s)
    end

    targets = [
      ["-0", "0"],
      ["+0", "0"],
      ["000123", "123"],
      ["-000123", "-123"],
    ]
    targets.each do |data, expected|
      assert_equal(expected, XSD::XSDLong.new(data).to_s)
    end

    targets = [
      9223372036854775808,
      -9223372036854775809,
      "0.0",
      "-5.2",
      "0.000000000000a",
      "+-5",
    ]
    targets.each do |d|
      assert_raises(XSD::ValueSpaceError) do
	XSD::XSDLong.new(d)
      end
    end
  end

  def test_XSDInt
    o = XSD::XSDInt.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::IntLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      0,
      123,
      -123,
      2147483647,
      -2147483648,
    ]
    targets.each do |lng|
      assert_equal(lng, XSD::XSDInt.new(lng).data)
    end

    targets = [
      "0",
      "123",
      "-123",
      "2147483647",
      "-2147483648",
    ]
    targets.each do |str|
      assert_equal(str, XSD::XSDInt.new(str).to_s)
    end

    targets = [
      ["-0", "0"],
      ["+0", "0"],
      ["000123", "123"],
      ["-000123", "-123"],
    ]
    targets.each do |data, expected|
      assert_equal(expected, XSD::XSDInt.new(data).to_s)
    end

    targets = [
      2147483648,
      -2147483649,
      "0.0",
      "-5.2",
      "0.000000000000a",
      "+-5",
    ]
    targets.each do |d|
      assert_raises(XSD::ValueSpaceError) do
	XSD::XSDInt.new(d)
      end
    end
  end
end


end
