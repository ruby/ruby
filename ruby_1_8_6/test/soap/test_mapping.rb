require 'test/unit'
require 'soap/mapping'


module SOAP


class TestMapping < Test::Unit::TestCase
  def test_date
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
    targets.each do |str, expectec|
      d = Date.parse(str)
      assert_equal(d.class, convert(d).class)
      assert_equal(d, convert(d))
    end
  end

  def test_datetime
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
    targets.each do |str, expectec|
      d = DateTime.parse(str)
      assert_equal(d.class, convert(d).class)
      assert_equal(d, convert(d))
    end
  end

  def convert(obj)
    SOAP::Mapping.soap2obj(SOAP::Mapping.obj2soap(obj))
  end
end


end
