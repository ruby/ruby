$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

ENV['TERM'] = 'xterm' # for some CI environments

require 'reline'
require 'test/unit'

begin
  require 'rbconfig'
rescue LoadError
end

begin
  # This should exist and available in load path when this file is mirrored to ruby/ruby and running at there
  if File.exist?(File.expand_path('../../tool/lib/envutil.rb', __dir__))
    require 'envutil'
  end
rescue LoadError
end

module Reline
  class <<self
    def test_mode(ansi: false)
      @original_iogate = IOGate

      if ENV['RELINE_TEST_ENCODING']
        encoding = Encoding.find(ENV['RELINE_TEST_ENCODING'])
      else
        encoding = Encoding::UTF_8
      end

      if ansi
        new_io_gate = ANSI.new
        # Setting ANSI gate's screen size through set_screen_size will also change the tester's stdin's screen size
        # Let's avoid that side-effect by stubbing the get_screen_size method
        new_io_gate.define_singleton_method(:get_screen_size) do
          [24, 80]
        end
        new_io_gate.define_singleton_method(:encoding) do
          encoding
        end
      else
        new_io_gate = Dumb.new(encoding: encoding)
      end

      remove_const('IOGate')
      const_set('IOGate', new_io_gate)
      core.config.instance_variable_set(:@test_mode, true)
      core.config.reset
    end

    def test_reset
      remove_const('IOGate')
      const_set('IOGate', @original_iogate)
      Reline.instance_variable_set(:@core, nil)
    end

    # Return a executable name to spawn Ruby process. In certain build configuration,
    # "ruby" may not be available.
    def test_rubybin
      # When this test suite is running in ruby/ruby, prefer EnvUtil result over original implementation
      if const_defined?(:EnvUtil)
        return EnvUtil.rubybin
      end

      # The following is a simplified port of EnvUtil.rubybin in ruby/ruby
      if ruby = ENV["RUBY"]
        return ruby
      end
      ruby = "ruby"
      exeext = RbConfig::CONFIG["EXEEXT"]
      rubyexe = (ruby + exeext if exeext and !exeext.empty?)
      if File.exist? ruby and File.executable? ruby and !File.directory? ruby
        return File.expand_path(ruby)
      end
      if rubyexe and File.exist? rubyexe and File.executable? rubyexe
        return File.expand_path(rubyexe)
      end
      if defined?(RbConfig.ruby)
        RbConfig.ruby
      else
        "ruby"
      end
    end
  end
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

  def input_raw_keys(input, convert = true)
    input = convert_str(input) if convert
    input.bytes.each do |b|
      @line_editor.input_key(Reline::Key.new(b, b, false))
    end
  end

  def assert_line_around_cursor(before, after)
    before = convert_str(before)
    after = convert_str(after)
    line = @line_editor.current_line
    byte_pointer = @line_editor.instance_variable_get(:@byte_pointer)
    actual_before = line.byteslice(0, byte_pointer)
    actual_after = line.byteslice(byte_pointer..)
    assert_equal([before, after], [actual_before, actual_after])
  end

  def assert_byte_pointer_size(expected)
    expected = convert_str(expected)
    byte_pointer = @line_editor.instance_variable_get(:@byte_pointer)
    chunk = @line_editor.line.byteslice(0, byte_pointer)
    assert_equal(
      expected.bytesize, byte_pointer,
      <<~EOM)
        <#{expected.inspect} (#{expected.encoding.inspect})> expected but was
        <#{chunk.inspect} (#{chunk.encoding.inspect})> in <Terminal #{Reline::Dumb.new.encoding.inspect}>
      EOM
  end

  def assert_line_index(expected)
    assert_equal(expected, @line_editor.instance_variable_get(:@line_index))
  end

  def assert_whole_lines(expected)
    assert_equal(expected, @line_editor.whole_lines)
  end

  def assert_key_binding(input, method_symbol, editing_modes = [:emacs, :vi_insert, :vi_command])
    editing_modes.each do |editing_mode|
      @config.editing_mode = editing_mode
      assert_equal(method_symbol, @config.editing_mode.default_key_bindings[input.bytes])
    end
  end
end
