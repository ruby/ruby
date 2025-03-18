# frozen_string_literal: true
require_relative 'helper'

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

    def test_scan_plus_inf
      assert_equal(1 / 0.0, ss.tokenize('+.inf'))
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
      assert_equal '_100', ss.tokenize('_100')
    end

    def test_scan_strings_starting_with_number
      assert_equal '450D', ss.tokenize('450D')
    end

    def test_scan_strings_ending_with_underscores
      assert_equal '100_', ss.tokenize('100_')
    end

    def test_scan_strings_with_legacy_int_delimiters
      assert_equal '0x_,_', ss.tokenize('0x_,_')
      assert_equal '+0__,,', ss.tokenize('+0__,,')
      assert_equal '-0b,_,', ss.tokenize('-0b,_,')
    end

    def test_scan_strings_with_strict_int_delimiters
      scanner = Psych::ScalarScanner.new ClassLoader.new, strict_integer: true
      assert_equal '0x___', scanner.tokenize('0x___')
      assert_equal '+0____', scanner.tokenize('+0____')
      assert_equal '-0b___', scanner.tokenize('-0b___')
    end

    def test_scan_int_commas_and_underscores
      # NB: This test is to ensure backward compatibility with prior Psych versions,
      # not to test against any actual YAML specification.
      assert_equal 123_456_789, ss.tokenize('123_456_789')
      assert_equal 123_456_789, ss.tokenize('123,456,789')
      assert_equal 123_456_789, ss.tokenize('1_2,3,4_5,6_789')

      assert_equal 1, ss.tokenize('1')
      assert_equal 1, ss.tokenize('+1')
      assert_equal(-1, ss.tokenize('-1'))

      assert_equal 0b010101010, ss.tokenize('0b010101010')
      assert_equal 0b010101010, ss.tokenize('0b0,1_0,1_,0,1_01,0')

      assert_equal 01234567, ss.tokenize('01234567')
      assert_equal 01234567, ss.tokenize('0_,,,1_2,_34567')

      assert_equal 0x123456789abcdef, ss.tokenize('0x123456789abcdef')
      assert_equal 0x123456789abcdef, ss.tokenize('0x12_,34,_56,_789abcdef')
      assert_equal 0x123456789abcdef, ss.tokenize('0x_12_,34,_56,_789abcdef')
      assert_equal 0x123456789abcdef, ss.tokenize('0x12_,34,_56,_789abcdef__')
    end

    def test_scan_strict_int_commas_and_underscores
      # this test is to ensure adherence to YML spec using the 'strict_integer' option
      scanner = Psych::ScalarScanner.new ClassLoader.new, strict_integer: true
      assert_equal 123_456_789, scanner.tokenize('123_456_789')
      assert_equal '123,456,789', scanner.tokenize('123,456,789')
      assert_equal '1_2,3,4_5,6_789', scanner.tokenize('1_2,3,4_5,6_789')

      assert_equal 1, scanner.tokenize('1')
      assert_equal 1, scanner.tokenize('+1')
      assert_equal(-1, scanner.tokenize('-1'))

      assert_equal 0b010101010, scanner.tokenize('0b010101010')
      assert_equal 0b010101010, scanner.tokenize('0b01_01_01_010')
      assert_equal '0b0,1_0,1_,0,1_01,0', scanner.tokenize('0b0,1_0,1_,0,1_01,0')

      assert_equal 01234567, scanner.tokenize('01234567')
      assert_equal '0_,,,1_2,_34567', scanner.tokenize('0_,,,1_2,_34567')

      assert_equal 0x123456789abcdef, scanner.tokenize('0x123456789abcdef')
      assert_equal 0x123456789abcdef, scanner.tokenize('0x12_34_56_789abcdef')
      assert_equal '0x12_,34,_56,_789abcdef', scanner.tokenize('0x12_,34,_56,_789abcdef')
      assert_equal '0x_12_,34,_56,_789abcdef', scanner.tokenize('0x_12_,34,_56,_789abcdef')
      assert_equal '0x12_,34,_56,_789abcdef__', scanner.tokenize('0x12_,34,_56,_789abcdef__')
    end

    def test_scan_dot
      assert_equal '.', ss.tokenize('.')
    end

    def test_scan_plus_dot
      assert_equal '+.', ss.tokenize('+.')
    end

    class MatchCallCounter < String
      attr_reader :match_call_count

      def match?(pat)
        @match_call_count ||= 0
        @match_call_count += 1
        super
      end
    end

    def test_scan_ascii_matches_quickly
      ascii = MatchCallCounter.new('abcdefghijklmnopqrstuvwxyz')
      ss.tokenize(ascii)
      assert_equal 1, ascii.match_call_count
    end

    def test_scan_unicode_matches_quickly
      unicode = MatchCallCounter.new('鳥かご関連用品')
      ss.tokenize(unicode)
      assert_equal 1, unicode.match_call_count
    end
  end
end
