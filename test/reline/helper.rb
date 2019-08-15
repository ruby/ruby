$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'reline'
require 'test/unit'

RELINE_TEST_ENCODING ||=
  if ENV['RELINE_TEST_ENCODING']
    Encoding.find(ENV['RELINE_TEST_ENCODING'])
  else
    Encoding::UTF_8
  end

class Reline::TestCase < Test::Unit::TestCase
=begin
  puts "Test encoding is #{RELINE_TEST_ENCODING}"
=end

  private def convert_str(input, options = {}, normalized = nil)
    return nil if input.nil?
    input.chars.map { |c|
      if Reline::Unicode::EscapedChars.include?(c.ord)
        c
      else
        c.encode(@line_editor.instance_variable_get(:@encoding), Encoding::UTF_8, options)
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
end
