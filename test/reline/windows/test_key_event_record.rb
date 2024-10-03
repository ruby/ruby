require_relative '../helper'
return unless Reline.const_defined?(:Windows)

class Reline::Windows
  class KeyEventRecord::Test < Reline::TestCase

    def setup
      # Ctrl+A
      @key = Reline::Windows::KeyEventRecord.new(0x41, 1, Reline::Windows::LEFT_CTRL_PRESSED)
    end

    def test_matches__with_no_arguments_raises_error
      assert_raise(ArgumentError) { @key.match? }
    end

    def test_matches_char_code
      assert @key.match?(char_code: 0x1)
    end

    def test_matches_virtual_key_code
      assert @key.match?(virtual_key_code: 0x41)
    end

    def test_matches_control_keys
      assert @key.match?(control_keys: :CTRL)
    end

    def test_doesnt_match_alt
      refute @key.match?(control_keys: :ALT)
    end

    def test_doesnt_match_empty_control_key
      refute @key.match?(control_keys: [])
    end

    def test_matches_control_keys_and_virtual_key_code
      assert @key.match?(control_keys: :CTRL, virtual_key_code: 0x41)
    end

  end
end
