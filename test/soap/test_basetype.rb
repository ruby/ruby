require 'test/unit'
require 'soap/baseData'


module SOAP


class TestSOAP < Test::Unit::TestCase
  NegativeZero = (-1.0 / (1.0 / 0.0))

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

  def test_SOAPNil
    o = SOAP::SOAPNil.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::NilLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    o = SOAP::SOAPNil.new(nil)
    assert_equal(true, o.is_nil)
    assert_equal(nil, o.data)
    assert_equal("", o.to_s)
    o = SOAP::SOAPNil.new('var')
    assert_equal(false, o.is_nil)
    assert_equal('var', o.data)
    assert_equal('var', o.to_s)
  end

  def test_SOAPString
    o = SOAP::SOAPString.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::StringLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    str = "abc"
    assert_equal(str, SOAP::SOAPString.new(str).data)
    assert_equal(str, SOAP::SOAPString.new(str).to_s)
    assert_raises(XSD::ValueSpaceError) do
      SOAP::SOAPString.new("\0")
    end
    assert_raises(XSD::ValueSpaceError) do
      p SOAP::SOAPString.new("\xC0\xC0").to_s
    end
  end

  def test_SOAPBoolean
    o = SOAP::SOAPBoolean.new
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
      assert_equal(expected, SOAP::SOAPBoolean.new(data).data)
      assert_equal(expected.to_s, SOAP::SOAPBoolean.new(data).to_s)
    end

    assert_raises(XSD::ValueSpaceError) do
      SOAP::SOAPBoolean.new("nil").to_s
    end
  end

  def test_SOAPDecimal
    o = SOAP::SOAPDecimal.new
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
      assert_equal(dec.to_s, SOAP::SOAPDecimal.new(dec).data)
    end

    targets = [
      "0",
      "0.00000001",
      "1000000000",
      "12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890",
      "-12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123.45678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789",
    ]
    targets.each do |str|
      assert_equal(str, SOAP::SOAPDecimal.new(str).to_s)
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
      assert_equal(expected, SOAP::SOAPDecimal.new(data).to_s)
    end

    targets = [
      "0.000000000000a",
      "00a.0000000000001",
      "+-5",
    ]
    targets.each do |d|
      assert_raises(XSD::ValueSpaceError) do
	SOAP::SOAPDecimal.new(d)
      end
    end
  end

  def test_SOAPFloat
    o = SOAP::SOAPFloat.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::FloatLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      3.14159265358979,
      12.34e36,
      1.402e-45,
      -1.402e-45,
    ]
    targets.each do |f|
      assert_equal(f, SOAP::SOAPFloat.new(f).data)
    end

    targets = [
      "+3.141592654",
      "+1.234e+37",
      "+1.402e-45",
      "-1.402e-45",
    ]
    targets.each do |f|
      assert_equal(f, SOAP::SOAPFloat.new(f).to_s)
    end

    targets = [
      [3, "+3"], 	# should be 3.0?
      [-2, "-2"],	# ditto
      [3.14159265358979, "+3.141592654"],
      [12.34e36, "+1.234e+37"],
      [1.402e-45, "+1.402e-45"],
      [-1.402e-45, "-1.402e-45"],
      ["1.402e", "+1.402"],
      ["12.34E36", "+1.234e+37"],
      ["1.402E-45", "+1.402e-45"],
      ["-1.402E-45", "-1.402e-45"],
      ["1.402E", "+1.402"],
    ]
    targets.each do |f, str|
      assert_equal(str, SOAP::SOAPFloat.new(f).to_s)
    end

    assert_equal("+0", SOAP::SOAPFloat.new(+0.0).to_s)
    assert_equal("-0", SOAP::SOAPFloat.new(NegativeZero).to_s)
    assert(SOAP::SOAPFloat.new(0.0/0.0).data.nan?)
    assert_equal("INF", SOAP::SOAPFloat.new(1.0/0.0).to_s)
    assert_equal(1, SOAP::SOAPFloat.new(1.0/0.0).data.infinite?)
    assert_equal("-INF", SOAP::SOAPFloat.new(-1.0/0.0).to_s)
    assert_equal(-1, SOAP::SOAPFloat.new(-1.0/0.0).data.infinite?)

    targets = [
      "0.000000000000a",
      "00a.0000000000001",
      "+-5",
      "5_0",
    ]
    targets.each do |d|
      assert_raises(XSD::ValueSpaceError) do
	SOAP::SOAPFloat.new(d)
      end
    end
  end

  def test_SOAPDouble
    o = SOAP::SOAPDouble.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::DoubleLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      3.14159265358979,
      12.34e36,
      1.402e-45,
      -1.402e-45,
    ]
    targets.each do |f|
      assert_equal(f, SOAP::SOAPDouble.new(f).data)
    end

    targets = [
      "+3.14159265358979",
      "+1.234e+37",
      "+1.402e-45",
      "-1.402e-45",
    ]
    targets.each do |f|
      assert_equal(f, SOAP::SOAPDouble.new(f).to_s)
    end

    targets = [
      [3, "+3"],	# should be 3.0?
      [-2, "-2"],	# ditto.
      [3.14159265358979, "+3.14159265358979"],
      [12.34e36, "+1.234e+37"],
      [1.402e-45, "+1.402e-45"],
      [-1.402e-45, "-1.402e-45"],
      ["1.402e", "+1.402"],
      ["12.34E36", "+1.234e+37"],
      ["1.402E-45", "+1.402e-45"],
      ["-1.402E-45", "-1.402e-45"],
      ["1.402E", "+1.402"],
    ]
    targets.each do |f, str|
      assert_equal(str, SOAP::SOAPDouble.new(f).to_s)
    end

    assert_equal("+0", SOAP::SOAPFloat.new(+0.0).to_s)
    assert_equal("-0", SOAP::SOAPFloat.new(NegativeZero).to_s)
    assert_equal("NaN", SOAP::SOAPDouble.new(0.0/0.0).to_s)
    assert(SOAP::SOAPDouble.new(0.0/0.0).data.nan?)
    assert_equal("INF", SOAP::SOAPDouble.new(1.0/0.0).to_s)
    assert_equal(1, SOAP::SOAPDouble.new(1.0/0.0).data.infinite?)
    assert_equal("-INF", SOAP::SOAPDouble.new(-1.0/0.0).to_s)
    assert_equal(-1, SOAP::SOAPDouble.new(-1.0/0.0).data.infinite?)

    targets = [
      "0.000000000000a",
      "00a.0000000000001",
      "+-5",
    ]
    targets.each do |d|
      assert_raises(XSD::ValueSpaceError) do
	SOAP::SOAPDouble.new(d)
      end
    end
  end

  def test_SOAPDuration
    o = SOAP::SOAPDuration.new
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
      assert_parsed_result(SOAP::SOAPDuration, str)
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
      assert_equal(expected, SOAP::SOAPDuration.new(data).to_s)
    end
  end

  def test_SOAPDateTime
    o = SOAP::SOAPDateTime.new
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
      "2002-12-31T23:59:59.51375Z",
      "2002-12-31T23:59:59.51345+12:34",
      "-2002-05-18T16:52:20Z",
      "-4711-12-31T23:59:59Z",
      "-4713-01-01T12:00:00Z",
      "-19999-12-31T23:59:59Z",
      "-2002-12-31T23:59:59+00:01",
      "-0001-12-31T23:59:59.00000000000000000001+13:30",
    ]
    targets.each do |str|
      assert_parsed_result(SOAP::SOAPDateTime, str)
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
      assert_equal(expected, SOAP::SOAPDateTime.new(data).to_s)
    end

    targets = [
      "1-05-18T16:52:20Z",
      "05-18T16:52:20Z",
      "2002-05T16:52:20Z",
      "2002-05-18T16:52Z",
      "",
    ]
    targets.each do |d|
      assert_raises(XSD::ValueSpaceError, d.to_s) do
	SOAP::SOAPDateTime.new(d)
      end
    end
  end

  def test_SOAPTime
    o = SOAP::SOAPTime.new
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
      "23:59:59.51375Z",
      "23:59:59.51375+12:34",
      "23:59:59+00:01",
    ]
    targets.each do |str|
      assert_parsed_result(SOAP::SOAPTime, str)
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
      assert_equal(expected, SOAP::SOAPTime.new(data).to_s)
    end
  end

  def test_SOAPDate
    o = SOAP::SOAPDate.new
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
      assert_parsed_result(SOAP::SOAPDate, str)
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
      assert_equal(expected, SOAP::SOAPDate.new(data).to_s)
    end
  end

  def test_SOAPGYearMonth
    o = SOAP::SOAPGYearMonth.new
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
      assert_parsed_result(SOAP::SOAPGYearMonth, str)
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
      assert_equal(expected, SOAP::SOAPGYearMonth.new(data).to_s)
    end
  end

  def test_SOAPGYear
    o = SOAP::SOAPGYear.new
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
      assert_parsed_result(SOAP::SOAPGYear, str)
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
      assert_equal(expected, SOAP::SOAPGYear.new(data).to_s)
    end
  end

  def test_SOAPGMonthDay
    o = SOAP::SOAPGMonthDay.new
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
      assert_parsed_result(SOAP::SOAPGMonthDay, str)
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
      assert_equal(expected, SOAP::SOAPGMonthDay.new(data).to_s)
    end
  end

  def test_SOAPGDay
    o = SOAP::SOAPGDay.new
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
      assert_parsed_result(SOAP::SOAPGDay, str)
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
      assert_equal(expected, SOAP::SOAPGDay.new(data).to_s)
    end
  end

  def test_SOAPGMonth
    o = SOAP::SOAPGMonth.new
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
      assert_parsed_result(SOAP::SOAPGMonth, str)
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
      assert_equal(expected, SOAP::SOAPGMonth.new(data).to_s)
    end
  end

  def test_SOAPHexBinary
    o = SOAP::SOAPHexBinary.new
    assert_equal(XSD::Namespace, o.type.namespace)
    assert_equal(XSD::HexBinaryLiteral, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      "abcdef",
      "\xe3\x81\xaa\xe3\x81\xb2",
      "\0",
      "",
    ]
    targets.each do |str|
      assert_equal(str, SOAP::SOAPHexBinary.new(str).string)
      assert_equal(str.unpack("H*")[0].tr('a-f', 'A-F'),
	SOAP::SOAPHexBinary.new(str).data)
      o = SOAP::SOAPHexBinary.new
      o.set_encoded(str.unpack("H*")[0].tr('a-f', 'A-F'))
      assert_equal(str, o.string)
      o.set_encoded(str.unpack("H*")[0].tr('A-F', 'a-f'))
      assert_equal(str, o.string)
    end

    targets = [
      "0FG7",
      "0fg7",
    ]
    targets.each do |d|
      assert_raises(XSD::ValueSpaceError, d.to_s) do
	o = SOAP::SOAPHexBinary.new
	o.set_encoded(d)
	p o.string
      end
    end
  end

  def test_SOAPBase64Binary
    o = SOAP::SOAPBase64.new
    assert_equal(SOAP::EncodingNamespace, o.type.namespace)
    assert_equal(SOAP::Base64Literal, o.type.name)
    assert_equal(nil, o.data)
    assert_equal(true, o.is_nil)

    targets = [
      "abcdef",
      "\xe3\x81\xaa\xe3\x81\xb2",
      "\0",
      "",
    ]
    targets.each do |str|
      assert_equal(str, SOAP::SOAPBase64.new(str).string)
      assert_equal([str].pack("m").chomp, SOAP::SOAPBase64.new(str).data)
      o = SOAP::SOAPBase64.new
      o.set_encoded([str].pack("m").chomp)
      assert_equal(str, o.string)
    end

    targets = [
      "-",
      "*",
    ]
    targets.each do |d|
      assert_raises(XSD::ValueSpaceError, d.to_s) do
	o = SOAP::SOAPBase64.new
	o.set_encoded(d)
	p o.string
      end
    end
  end

  def test_SOAPAnyURI
    o = SOAP::SOAPAnyURI.new
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
      assert_parsed_result(SOAP::SOAPAnyURI, str)
    end
  end

  def test_SOAPQName
    o = SOAP::SOAPQName.new
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
      assert_parsed_result(SOAP::SOAPQName, str)
    end
  end


  ###
  ## Derived types
  #

  def test_SOAPInteger
    o = SOAP::SOAPInteger.new
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
      assert_equal(int, SOAP::SOAPInteger.new(int).data)
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
      assert_equal(str, SOAP::SOAPInteger.new(str).to_s)
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
      assert_equal(expected, SOAP::SOAPInteger.new(data).to_s)
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
	SOAP::SOAPInteger.new(d)
      end
    end
  end

  def test_SOAPLong
    o = SOAP::SOAPLong.new
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
      assert_equal(lng, SOAP::SOAPLong.new(lng).data)
    end

    targets = [
      "0",
      "123",
      "-123",
      "9223372036854775807",
      "-9223372036854775808",
    ]
    targets.each do |str|
      assert_equal(str, SOAP::SOAPLong.new(str).to_s)
    end

    targets = [
      ["-0", "0"],
      ["+0", "0"],
      ["000123", "123"],
      ["-000123", "-123"],
    ]
    targets.each do |data, expected|
      assert_equal(expected, SOAP::SOAPLong.new(data).to_s)
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
	SOAP::SOAPLong.new(d)
      end
    end
  end

  def test_SOAPInt
    o = SOAP::SOAPInt.new
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
      assert_equal(lng, SOAP::SOAPInt.new(lng).data)
    end

    targets = [
      "0",
      "123",
      "-123",
      "2147483647",
      "-2147483648",
    ]
    targets.each do |str|
      assert_equal(str, SOAP::SOAPInt.new(str).to_s)
    end

    targets = [
      ["-0", "0"],
      ["+0", "0"],
      ["000123", "123"],
      ["-000123", "-123"],
    ]
    targets.each do |data, expected|
      assert_equal(expected, SOAP::SOAPInt.new(data).to_s)
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
	SOAP::SOAPInt.new(d)
      end
    end
  end
end


end
