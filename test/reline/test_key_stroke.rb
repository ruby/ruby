require_relative 'helper'

class Reline::KeyStroke::Test < Reline::TestCase
  def encoding
    Reline.core.encoding
  end

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
    stroke = Reline::KeyStroke.new(config, encoding)
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
    stroke = Reline::KeyStroke.new(config, encoding)
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
      'abc' => 'AB',
      'ab' => "1\C-a"
    }.each_pair do |key, func|
      config.add_default_key_binding(key.bytes, func.bytes)
    end
    stroke = Reline::KeyStroke.new(config, encoding)
    assert_equal([[Reline::Key.new('A', :ed_insert, false), Reline::Key.new('B', :ed_insert, false)], 'de'.bytes], stroke.expand('abcde'.bytes))
    assert_equal([[Reline::Key.new('1', :ed_digit, false), Reline::Key.new("\C-a", :ed_move_to_beg, false)], 'de'.bytes], stroke.expand('abde'.bytes))
    # CSI sequence
    assert_equal([[], 'bc'.bytes], stroke.expand("\e[1;2;3;4;5abc".bytes))
    assert_equal([[], 'BC'.bytes], stroke.expand("\e\e[ABC".bytes))
    # SS3 sequence
    assert_equal([[], 'QR'.bytes], stroke.expand("\eOPQR".bytes))
  end

  def test_oneshot_key_bindings
    config = Reline::Config.new
    {
      'abc'.bytes => '123',
      # IRB version <= 1.13.1 wrongly uses Reline::Key with wrong argument. It should be ignored without error.
      [Reline::Key.new(nil, 0xE4, true)] => '012',
      "\eda".bytes => 'abc', # Alt+d a
      [195, 164] => 'def'
    }.each_pair do |key, func|
      config.add_oneshot_key_binding(key, func.bytes)
    end
    stroke = Reline::KeyStroke.new(config, encoding)
    assert_equal(Reline::KeyStroke::UNMATCHED, stroke.match_status('zzz'.bytes))
    assert_equal(Reline::KeyStroke::MATCHED, stroke.match_status('abc'.bytes))
    assert_equal(Reline::KeyStroke::UNMATCHED, stroke.match_status('da'.bytes))
    assert_equal(Reline::KeyStroke::MATCHED, stroke.match_status("\eda".bytes))
    assert_equal(Reline::KeyStroke::UNMATCHED, stroke.match_status(" \eda".bytes))
    assert_equal(Reline::KeyStroke::MATCHED, stroke.match_status([195, 164]))
  end

  def test_multibyte_matching
    begin
      char = 'あ'.encode(encoding)
    rescue Encoding::UndefinedConversionError
      omit
    end
    config = Reline::Config.new
    stroke = Reline::KeyStroke.new(config, encoding)
    key = Reline::Key.new(char, :ed_insert, false)
    bytes = char.bytes
    assert_equal(Reline::KeyStroke::MATCHED, stroke.match_status(bytes))
    assert_equal([[key], []], stroke.expand(bytes))
    assert_equal(Reline::KeyStroke::UNMATCHED, stroke.match_status(bytes * 2))
    assert_equal([[key], bytes], stroke.expand(bytes * 2))
    (1...bytes.size).each do |i|
      partial_bytes = bytes.take(i)
      assert_equal(Reline::KeyStroke::MATCHING_MATCHED, stroke.match_status(partial_bytes))
      assert_equal([[], []], stroke.expand(partial_bytes))
    end
  end
end
