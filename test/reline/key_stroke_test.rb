require 'helper'

class Reline::KeyStroke::Test < Reline::TestCase
  using Module.new {
    refine Array do
      def as_s
        map(&:chr).join
      end
    end
  }

  def test_input_to!
    config = {
      key_mapping: {
        "a" => "xx",
        "ab" => "y",
        "abc" => "z",
        "x" => "rr"
      }
    }
    stroke = Reline::KeyStroke.new(config)
    result = ("abzwabk".bytes).map { |char|
      stroke.input_to!(char)&.then { |result|
        "#{result.as_s}"
      }
    }
    assert_equal(result, [nil, nil, "yz", "w", nil, nil, "yk"])
  end

  def test_input_to
    config = {
      key_mapping: {
        "a" => "xx",
        "ab" => "y",
        "abc" => "z",
        "x" => "rr"
      }
    }
    stroke = Reline::KeyStroke.new(config)
    assert_equal(stroke.input_to("a".bytes)&.as_s, nil)
    assert_equal(stroke.input_to("ab".bytes)&.as_s, nil)
    assert_equal(stroke.input_to("abc".bytes)&.as_s, "z")
    assert_equal(stroke.input_to("abz".bytes)&.as_s, "yz")
    assert_equal(stroke.input_to("abx".bytes)&.as_s, "yrr")
    assert_equal(stroke.input_to("ac".bytes)&.as_s, "rrrrc")
    assert_equal(stroke.input_to("aa".bytes)&.as_s, "rrrrrrrr")
    assert_equal(stroke.input_to("x".bytes)&.as_s, "rr")
    assert_equal(stroke.input_to("m".bytes)&.as_s, "m")
    assert_equal(stroke.input_to("abzwabk".bytes)&.as_s, "yzwabk")
  end
end
