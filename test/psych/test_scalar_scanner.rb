# frozen_string_literal: true
require_relative 'helper'
require 'date'

module Psych
  class TestScalarScanner < TestCase
    attr_reader :ss

    def setup
      super
      @ss = Psych::ScalarScanner.new ClassLoader.new
    end

    def test_scan_time
      { '2001-12-15T02:59:43.1Z' => Time.utc(2001, 12, 15, 02, 59, 43, 100000),
        '2001-12-14t21:59:43.10-05:00' => Time.utc(2001, 12, 15, 02, 59, 43, 100000),
        '2001-12-14 21:59:43.10 -5' => Time.utc(2001, 12, 15, 02, 59, 43, 100000),
        '2001-12-15 2:59:43.10' => Time.utc(2001, 12, 15, 02, 59, 43, 100000),
        '2011-02-24 11:17:06 -0800' => Time.utc(2011, 02, 24, 19, 17, 06)
      }.each do |time_str, time|
        assert_equal time, @ss.tokenize(time_str)
      end
    end

    def test_scan_bad_time
      [ '2001-12-15T02:59:73.1Z',
        '2001-12-14t90:59:43.10-05:00',
        '2001-92-14 21:59:43.10 -5',
        '2001-12-15 92:59:43.10',
        '2011-02-24 81:17:06 -0800',
      ].each do |time_str|
        assert_equal time_str, @ss.tokenize(time_str)
      end
    end

    def test_scan_bad_dates
      x = '2000-15-01'
      assert_equal x, @ss.tokenize(x)

      x = '2000-10-51'
      assert_equal x, @ss.tokenize(x)

      x = '2000-10-32'
      assert_equal x, @ss.tokenize(x)
    end

    def test_scan_good_edge_date
      x = '2000-1-31'
      assert_equal Date.strptime(x, '%Y-%m-%d'), @ss.tokenize(x)
    end

    def test_scan_bad_edge_date
      x = '2000-11-31'
      assert_equal x, @ss.tokenize(x)
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

    def test_scan_float_with_exponent_but_no_fraction
      assert_equal(0.0, ss.tokenize('0.E+0'))
    end

    def test_scan_null
      assert_nil ss.tokenize('null')
      assert_nil ss.tokenize('~')
      assert_nil ss.tokenize('')
    end

    def test_scan_symbol
      assert_equal :foo, ss.tokenize(':foo')
    end

    def test_scan_not_sexagesimal
      assert_equal '00:00:00:00:0f', ss.tokenize('00:00:00:00:0f')
      assert_equal '00:00:00:00:00', ss.tokenize('00:00:00:00:00')
      assert_equal '00:00:00:00:00.0', ss.tokenize('00:00:00:00:00.0')
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

    def test_scan_strings_starting_with_underscores
      assert_equal "_100", ss.tokenize('_100')
    end
  end
end
