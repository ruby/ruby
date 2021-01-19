$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'reline'
require 'test/unit'

module Reline
  class <<self
    def test_mode
        remove_const('IOGate') if const_defined?('IOGate')
        const_set('IOGate', Reline::GeneralIO)
        Reline::GeneralIO.reset
        send(:core).config.instance_variable_set(:@test_mode, true)
        send(:core).config.reset
    end

    def test_reset
      Reline.instance_variable_set(:@core, nil)
    end
  end
end

def start_pasting
  Reline::GeneralIO.start_pasting
end

def finish_pasting
  Reline::GeneralIO.finish_pasting
end

RELINE_TEST_ENCODING ||=
  if ENV['RELINE_TEST_ENCODING']
    Encoding.find(ENV['RELINE_TEST_ENCODING'])
  else
    Encoding::UTF_8
  end

class Reline::TestCase < Test::Unit::TestCase
  private def convert_str(input, options = {}, normalized = nil)
    return nil if input.nil?
    input.chars.map { |c|
      if Reline::Unicode::EscapedChars.include?(c.ord)
        c
      else
        c.encode(@line_editor.instance_variable_get(:@encoding), Encoding::UTF_8, **options)
      end
    }.join
  rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
    input.unicode_normalize!(:nfc)
    if normalized
      options[:undef] = :replace
      options[:replace] = '?'
    end
    normalized = true
    retry
  end

  def input_key_by_symbol(input)
    @line_editor.input_key(Reline::Key.new(input, input, false))
  end

  def input_keys(input, convert = true)
    input = convert_str(input) if convert
    input.chars.each do |c|
      if c.bytesize == 1
        eighth_bit = 0b10000000
        byte = c.bytes.first
        if byte.allbits?(eighth_bit)
          @line_editor.input_key(Reline::Key.new(byte ^ eighth_bit, byte, true))
        else
          @line_editor.input_key(Reline::Key.new(byte, byte, false))
        end
      else
        c.bytes.each do |b|
          @line_editor.input_key(Reline::Key.new(b, b, false))
        end
      end
    end
  end

  def assert_line(expected)
    expected = convert_str(expected)
    assert_equal(expected, @line_editor.line)
  end

  def assert_byte_pointer_size(expected)
    expected = convert_str(expected)
    byte_pointer = @line_editor.instance_variable_get(:@byte_pointer)
    assert_equal(
      expected.bytesize, byte_pointer,
      "<#{expected.inspect}> expected but was\n<#{@line_editor.line.byteslice(0, byte_pointer).inspect}>")
  end

  def assert_cursor(expected)
    assert_equal(expected, @line_editor.instance_variable_get(:@cursor))
  end

  def assert_cursor_max(expected)
    assert_equal(expected, @line_editor.instance_variable_get(:@cursor_max))
  end

  def assert_line_index(expected)
    assert_equal(expected, @line_editor.instance_variable_get(:@line_index))
  end

  def assert_whole_lines(expected)
    previous_line_index = @line_editor.instance_variable_get(:@previous_line_index)
    if previous_line_index
      lines = @line_editor.whole_lines(index: previous_line_index)
    else
      lines = @line_editor.whole_lines
    end
    assert_equal(expected, lines)
  end
end
