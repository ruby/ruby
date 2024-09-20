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
    config = Reline::Config.new
    {
      'a' => 'xx',
      'ab' => 'y',
      'abc' => 'z',
      'x' => 'rr'
    }.each_pair do |key, func|
      config.add_default_key_binding(key.bytes, func.bytes)
    end
    stroke = Reline::KeyStroke.new(config)
    assert_equal(Reline::KeyStroke::MATCHING_MATCHED, stroke.match_status("a".bytes))
    assert_equal(Reline::KeyStroke::MATCHING_MATCHED, stroke.match_status("ab".bytes))
    assert_equal(Reline::KeyStroke::MATCHED, stroke.match_status("abc".bytes))
    assert_equal(Reline::KeyStroke::UNMATCHED, stroke.match_status("abz".bytes))
    assert_equal(Reline::KeyStroke::UNMATCHED, stroke.match_status("abcx".bytes))
    assert_equal(Reline::KeyStroke::UNMATCHED, stroke.match_status("aa".bytes))
    assert_equal(Reline::KeyStroke::MATCHED, stroke.match_status("x".bytes))
    assert_equal(Reline::KeyStroke::UNMATCHED, stroke.match_status("xa".bytes))
  end

  def test_match_unknown
    config = Reline::Config.new
    config.add_default_key_binding("\e[9abc".bytes, 'x')
    stroke = Reline::KeyStroke.new(config)
    sequences = [
      "\e[9abc",
      "\e[9d",
      "\e[A", # Up
      "\e[1;1R", # Cursor position report
      "\e[15~", # F5
      "\eOP", # F1
      "\e\e[A", # Option+Up
      "\eX",
      "\e\eX"
    ]
    sequences.each do |seq|
      assert_equal(Reline::KeyStroke::MATCHED, stroke.match_status(seq.bytes))
      assert_equal(Reline::KeyStroke::UNMATCHED, stroke.match_status(seq.bytes + [32]))
      (2...seq.size).each do |i|
        assert_equal(Reline::KeyStroke::MATCHING, stroke.match_status(seq.bytes.take(i)))
      end
    end
  end

  def test_expand
    config = Reline::Config.new
    {
      'abc' => '123',
      'ab' => '456'
    }.each_pair do |key, func|
      config.add_default_key_binding(key.bytes, func.bytes)
    end
    stroke = Reline::KeyStroke.new(config)
    assert_equal(['123'.bytes.map { |c| Reline::Key.new(c, c, false) }, 'de'.bytes], stroke.expand('abcde'.bytes))
    assert_equal(['456'.bytes.map { |c| Reline::Key.new(c, c, false) }, 'de'.bytes], stroke.expand('abde'.bytes))
    # CSI sequence
    assert_equal([[], 'bc'.bytes], stroke.expand("\e[1;2;3;4;5abc".bytes))
    assert_equal([[], 'BC'.bytes], stroke.expand("\e\e[ABC".bytes))
    # SS3 sequence
    assert_equal([[], 'QR'.bytes], stroke.expand("\eOPQR".bytes))
  end

  def test_oneshot_key_bindings
    config = Reline::Config.new
    {
      'abc' => '123',
    }.each_pair do |key, func|
      config.add_default_key_binding(key.bytes, func.bytes)
    end
    stroke = Reline::KeyStroke.new(config)
    assert_equal(Reline::KeyStroke::UNMATCHED, stroke.match_status('zzz'.bytes))
    assert_equal(Reline::KeyStroke::MATCHED, stroke.match_status('abc'.bytes))
  end

  def test_with_reline_key
    config = Reline::Config.new
    {
      "\eda".bytes => 'abc', # Alt+d a
      [195, 164] => 'def'
    }.each_pair do |key, func|
      config.add_oneshot_key_binding(key, func.bytes)
    end
    stroke = Reline::KeyStroke.new(config)
    assert_equal(Reline::KeyStroke::UNMATCHED, stroke.match_status('da'.bytes))
    assert_equal(Reline::KeyStroke::MATCHED, stroke.match_status("\eda".bytes))
    assert_equal(Reline::KeyStroke::UNMATCHED, stroke.match_status([32, 195, 164]))
    assert_equal(Reline::KeyStroke::MATCHED, stroke.match_status([195, 164]))
  end
end
