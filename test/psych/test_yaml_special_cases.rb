# frozen_string_literal: true

require_relative 'helper'

require 'stringio'
require 'tempfile'

module Psych
  class TestYamlSpecialCases < TestCase
    def setup
      super
    end

    def test_empty_string
      s = ""
      assert_equal false, Psych.load(s)
      assert_equal [], Psych.load_stream(s)
      assert_equal false, Psych.parse(s)
      assert_equal [], Psych.parse_stream(s).transform
      assert_nil   Psych.safe_load(s)
    end

    def test_false
      s = "false"
      assert_equal false, Psych.load(s)
      assert_equal [false], Psych.load_stream(s)
      assert_equal false, Psych.parse(s).transform
      assert_equal [false], Psych.parse_stream(s).transform
      assert_equal false, Psych.safe_load(s)
    end

    def test_n
      s = "n"
      assert_equal "n", Psych.load(s)
      assert_equal ["n"], Psych.load_stream(s)
      assert_equal "n", Psych.parse(s).transform
      assert_equal ["n"], Psych.parse_stream(s).transform
      assert_equal "n", Psych.safe_load(s)
    end

    def test_off
      s = "off"
      assert_equal false, Psych.load(s)
      assert_equal [false], Psych.load_stream(s)
      assert_equal false, Psych.parse(s).transform
      assert_equal [false], Psych.parse_stream(s).transform
      assert_equal false, Psych.safe_load(s)
    end

    def test_inf
      s = "-.inf"
      assert_equal(-Float::INFINITY, Psych.load(s))
      assert_equal([-Float::INFINITY], Psych.load_stream(s))
      assert_equal(-Float::INFINITY, Psych.parse(s).transform)
      assert_equal([-Float::INFINITY], Psych.parse_stream(s).transform)
      assert_equal(-Float::INFINITY, Psych.safe_load(s))
    end

    def test_NaN
      s = ".NaN"
      assert Float::NAN, Psych.load(s).nan?
      assert [Float::NAN], Psych.load_stream(s).first.nan?
      assert Psych.parse(s).transform.nan?
      assert Psych.parse_stream(s).transform.first.nan?
      assert Psych.safe_load(s).nan?
    end

    def test_0xC
      s = "0xC"
      assert_equal 12, Psych.load(s)
      assert_equal [12], Psych.load_stream(s)
      assert_equal 12, Psych.parse(s).transform
      assert_equal [12], Psych.parse_stream(s).transform
      assert_equal 12, Psych.safe_load(s)
    end

    def test_arrows
      s = "<<"
      assert_equal "<<", Psych.load(s)
      assert_equal ["<<"], Psych.load_stream(s)
      assert_equal "<<", Psych.parse(s).transform
      assert_equal ["<<"], Psych.parse_stream(s).transform
      assert_equal "<<", Psych.safe_load(s)
    end

    def test_arrows_hash
      s = "<<: {}"
      assert_equal({}, Psych.load(s))
      assert_equal [{}], Psych.load_stream(s)
      assert_equal({}, Psych.parse(s).transform)
      assert_equal [{}], Psych.parse_stream(s).transform
      assert_equal({}, Psych.safe_load(s))
    end

    def test_thousand
      s = "- 1000\n- +1000\n- 1_000"
      assert_equal [1000, 1000, 1000], Psych.load(s)
      assert_equal [[1000, 1000, 1000]], Psych.load_stream(s)
      assert_equal [1000, 1000, 1000], Psych.parse(s).transform
      assert_equal [[1000, 1000, 1000]], Psych.parse_stream(s).transform
      assert_equal [1000, 1000, 1000], Psych.safe_load(s)
    end

    def test_8
      s = "[8, 08, 0o10, 010]"
      assert_equal [8, "08", "0o10", 8], Psych.load(s)
      assert_equal [[8, "08", "0o10", 8]], Psych.load_stream(s)
      assert_equal [8, "08", "0o10", 8], Psych.parse(s).transform
      assert_equal [[8, "08", "0o10", 8]], Psych.parse_stream(s).transform
      assert_equal [8, "08", "0o10", 8], Psych.safe_load(s)
    end

    def test_null
      s = "null"
      assert_nil   Psych.load(s)
      assert_equal [nil], Psych.load_stream(s)
      assert_nil   Psych.parse(s).transform
      assert_equal [nil], Psych.parse_stream(s).transform
      assert_nil   Psych.safe_load(s)
    end

    private

    def special_case_cycle(object)
      %w[load load_stream parse parse_stream safe_load].map do |m|
        Psych.public_send(m, object)
      end
    end
  end
end
