require_relative 'helper'

class Reline::KeyStroke::Test < Reline::TestCase
  using Module.new {
    refine Array do
      def as_s
        join
      end

      def to_keys
        map{ |b| Reline::Key.new(b, b, false) }
      end
    end
  }

  def test_match_status
    config = {
      key_mapping: {
        "a" => "xx",
        "ab" => "y",
        "abc" => "z",
        "x" => "rr"
      }
    }
    stroke = Reline::KeyStroke.new(config)
    assert_equal(:matching, stroke.match_status("a".bytes))
    assert_equal(:matching, stroke.match_status("ab".bytes))
    assert_equal(:matched, stroke.match_status("abc".bytes))
    assert_equal(:matched, stroke.match_status("abz".bytes))
    assert_equal(:matched, stroke.match_status("abx".bytes))
    assert_equal(:matched, stroke.match_status("ac".bytes))
    assert_equal(:matched, stroke.match_status("aa".bytes))
    assert_equal(:matched, stroke.match_status("x".bytes))
    assert_equal(:unmatched, stroke.match_status("m".bytes))
    assert_equal(:matched, stroke.match_status("abzwabk".bytes))
  end
end
