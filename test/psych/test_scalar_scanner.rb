require_relative 'helper'

module Psych
  class TestScalarScanner < TestCase
    def test_scan_time
      [ '2001-12-15T02:59:43.1Z',
        '2001-12-14t21:59:43.10-05:00',
        '2001-12-14 21:59:43.10 -5',
        '2010-01-06 00:00:00 -08:00',
        '2001-12-15 2:59:43.10',
      ].each do |time|
        ss = Psych::ScalarScanner.new
        assert_instance_of Time, ss.tokenize(time)
      end
    end

    attr_reader :ss

    def setup
      super
      @ss = Psych::ScalarScanner.new
    end

    def test_scan_date
      date = '1980-12-16'
      token = @ss.tokenize date
      assert_equal 1980, token.year
      assert_equal 12, token.month
      assert_equal 16, token.day
    end

    def test_scan_inf
      assert_equal(1 / 0.0, ss.tokenize('.inf'))
    end

    def test_scan_minus_inf
      assert_equal(-1 / 0.0, ss.tokenize('-.inf'))
    end

    def test_scan_nan
      assert ss.tokenize('.nan').nan?
    end

    def test_scan_null
      assert_equal nil, ss.tokenize('null')
      assert_equal nil, ss.tokenize('~')
      assert_equal nil, ss.tokenize('')
    end

    def test_scan_symbol
      assert_equal :foo, ss.tokenize(':foo')
    end

    def test_scan_sexagesimal_float
      assert_equal 685230.15, ss.tokenize('190:20:30.15')
    end

    def test_scan_sexagesimal_int
      assert_equal 685230, ss.tokenize('190:20:30')
    end

    def test_scan_float
      assert_equal 1.2, ss.tokenize('1.2')
    end

    def test_scan_true
      assert_equal true, ss.tokenize('true')
    end
  end
end
