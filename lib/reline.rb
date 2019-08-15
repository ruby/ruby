require 'io/console'
require 'timeout'
require 'reline/version'
require 'reline/config'
require 'reline/key_actor'
require 'reline/key_stroke'
require 'reline/line_editor'
require 'reline/history'

module Reline
  Key = Struct.new('Key', :char, :combined_char, :with_meta)

  extend self
  FILENAME_COMPLETION_PROC = nil
  USERNAME_COMPLETION_PROC = nil

  if RbConfig::CONFIG['host_os'] =~ /mswin|msys|mingw|cygwin|bccwin|wince|emc/
    IS_WINDOWS = true
  else
    IS_WINDOWS = false
  end

  CursorPos = Struct.new(:x, :y)

  @@config = Reline::Config.new
  @@key_stroke = Reline::KeyStroke.new(@@config)
  @@line_editor = Reline::LineEditor.new(@@config)
  @@ambiguous_width = nil

  HISTORY = History.new(@@config)

  @@completion_append_character = nil
  def self.completion_append_character
    @@completion_append_character
  end
  def self.completion_append_character=(val)
    if val.nil?
      @@completion_append_character = nil
    elsif val.size == 1
      @@completion_append_character = val.encode(Encoding::default_external)
    elsif val.size > 1
      @@completion_append_character = val[0].encode(Encoding::default_external)
    else
      @@completion_append_character = nil
    end
  end

  @@basic_word_break_characters = " \t\n`><=;|&{("
  def self.basic_word_break_characters
    @@basic_word_break_characters
  end
  def self.basic_word_break_characters=(v)
    @@basic_word_break_characters = v.encode(Encoding::default_external)
  end

  @@completer_word_break_characters = @@basic_word_break_characters.dup
  def self.completer_word_break_characters
    @@completer_word_break_characters
  end
  def self.completer_word_break_characters=(v)
    @@completer_word_break_characters = v.encode(Encoding::default_external)
  end

  @@basic_quote_characters = '"\''
  def self.basic_quote_characters
    @@basic_quote_characters
  end
  def self.basic_quote_characters=(v)
    @@basic_quote_characters = v.encode(Encoding::default_external)
  end

  @@completer_quote_characters = '"\''
  def self.completer_quote_characters
    @@completer_quote_characters
  end
  def self.completer_quote_characters=(v)
    @@completer_quote_characters = v.encode(Encoding::default_external)
  end

  @@filename_quote_characters = ''
  def self.filename_quote_characters
    @@filename_quote_characters
  end
  def self.filename_quote_characters=(v)
    @@filename_quote_characters = v.encode(Encoding::default_external)
  end

  @@special_prefixes = ''
  def self.special_prefixes
    @@special_prefixes
  end
  def self.special_prefixes=(v)
    @@special_prefixes = v.encode(Encoding::default_external)
  end

  @@completion_case_fold = nil
  def self.completion_case_fold
    @@completion_case_fold
  end
  def self.completion_case_fold=(v)
    @@completion_case_fold = v
  end

  @@completion_proc = nil
  def self.completion_proc
    @@completion_proc
  end
  def self.completion_proc=(p)
    raise ArgumentError unless p.is_a?(Proc)
    @@completion_proc = p
  end

  @@output_modifier_proc = nil
  def self.output_modifier_proc
    @@output_modifier_proc
  end
  def self.output_modifier_proc=(p)
    raise ArgumentError unless p.is_a?(Proc)
    @@output_modifier_proc = p
  end

  @@prompt_proc = nil
  def self.prompt_proc
    @@prompt_proc
  end
  def self.prompt_proc=(p)
    raise ArgumentError unless p.is_a?(Proc)
    @@prompt_proc = p
  end

  @@auto_indent_proc = nil
  def self.auto_indent_proc
    @@auto_indent_proc
  end
  def self.auto_indent_proc=(p)
    raise ArgumentError unless p.is_a?(Proc)
    @@auto_indent_proc = p
  end

  @@pre_input_hook = nil
  def self.pre_input_hook
    @@pre_input_hook
  end
  def self.pre_input_hook=(p)
    @@pre_input_hook = p
  end

  @@dig_perfect_match_proc = nil
  def self.dig_perfect_match_proc
    @@dig_perfect_match_proc
  end
  def self.dig_perfect_match_proc=(p)
    raise ArgumentError unless p.is_a?(Proc)
    @@dig_perfect_match_proc = p
  end

  def self.insert_text(text)
    @@line_editor&.insert_text(text)
    self
  end

  def self.redisplay
    @@line_editor&.rerender
  end

  def self.line_buffer
    @@line_editor&.line
  end

  def self.point
    @@line_editor ? @@line_editor.byte_pointer : 0
  end

  def self.point=(val)
    @@line_editor.byte_pointer = val
  end

  def self.delete_text(start = nil, length = nil)
    @@line_editor&.delete_text(start, length)
  end

  private_class_method def self.test_mode
    remove_const('IOGate') if const_defined?('IOGate')
    const_set('IOGate', Reline::GeneralIO)
    @@config.instance_variable_set(:@test_mode, true)
    @@config.reset
  end

  def self.input=(val)
    raise TypeError unless val.respond_to?(:getc) or val.nil?
    if val.respond_to?(:getc)
      if defined?(Reline::ANSI) and IOGate == Reline::ANSI
        Reline::ANSI.input = val
      elsif IOGate == Reline::GeneralIO
        Reline::GeneralIO.input = val
      end
    end
  end

  @@output = STDOUT
  def self.output=(val)
    raise TypeError unless val.respond_to?(:write) or val.nil?
    @@output = val
    if defined?(Reline::ANSI) and IOGate == Reline::ANSI
      Reline::ANSI.output = val
    end
  end

  def self.vi_editing_mode
    @@config.editing_mode = :vi_insert
    nil
  end

  def self.emacs_editing_mode
    @@config.editing_mode = :emacs
    nil
  end

  def self.vi_editing_mode?
    @@config.editing_mode_is?(:vi_insert, :vi_command)
  end

  def self.emacs_editing_mode?
    @@config.editing_mode_is?(:emacs)
  end

  def self.get_screen_size
    Reline::IOGate.get_screen_size
  end

  def eof?
    @@line_editor.eof?
  end

  def readmultiline(prompt = '', add_hist = false, &confirm_multiline_termination)
    unless confirm_multiline_termination
      raise ArgumentError.new('#readmultiline needs block to confirm multiline termination')
    end
    inner_readline(prompt, add_hist, true, &confirm_multiline_termination)

    whole_buffer = @@line_editor.whole_buffer.dup
    whole_buffer.taint
    if add_hist and whole_buffer and whole_buffer.chomp.size > 0
      Reline::HISTORY << whole_buffer
    end

    @@line_editor.reset_line if @@line_editor.whole_buffer.nil?
    whole_buffer
  end

  def readline(prompt = '', add_hist = false)
    inner_readline(prompt, add_hist, false)

    line = @@line_editor.line.dup
    line.taint
    if add_hist and line and line.chomp.size > 0
      Reline::HISTORY << line.chomp
    end

    @@line_editor.reset_line if @@line_editor.line.nil?
    line
  end

  def inner_readline(prompt, add_hist, multiline, &confirm_multiline_termination)
    if ENV['RELINE_STDERR_TTY']
      $stderr.reopen(ENV['RELINE_STDERR_TTY'], 'w')
      $stderr.sync = true
      $stderr.puts "Reline is used by #{Process.pid}"
    end
    otio = Reline::IOGate.prep

    may_req_ambiguous_char_width
    @@line_editor.reset(prompt)
    if multiline
      @@line_editor.multiline_on
      if block_given?
        @@line_editor.confirm_multiline_termination_proc = confirm_multiline_termination
      end
    else
      @@line_editor.multiline_off
    end
    @@line_editor.output = @@output
    @@line_editor.completion_proc = @@completion_proc
    @@line_editor.output_modifier_proc = @@output_modifier_proc
    @@line_editor.prompt_proc = @@prompt_proc
    @@line_editor.auto_indent_proc = @@auto_indent_proc
    @@line_editor.dig_perfect_match_proc = @@dig_perfect_match_proc
    @@line_editor.pre_input_hook = @@pre_input_hook
    @@line_editor.rerender

    unless @@config.test_mode
      @@config.read
      @@config.reset_default_key_bindings
      Reline::IOGate::RAW_KEYSTROKE_CONFIG.each_pair do |key, func|
        @@config.add_default_key_binding(key, func)
      end
    end

    begin
      loop do
        read_io(@@config.keyseq_timeout) { |inputs|
          inputs.each { |c|
            @@line_editor.input_key(c)
            @@line_editor.rerender
          }
        }
        break if @@line_editor.finished?
      end
      Reline::IOGate.move_cursor_column(0)
    rescue StandardError => e
      @@line_editor.finalize
      Reline::IOGate.deprep(otio)
      raise e
    end

    @@line_editor.finalize
    Reline::IOGate.deprep(otio)
  end

  # Keystrokes of GNU Readline will timeout it with the specification of
  # "keyseq-timeout" when waiting for the 2nd character after the 1st one.
  # If the 2nd character comes after 1st ESC without timeout it has a
  # meta-property of meta-key to discriminate modified key with meta-key
  # from multibyte characters that come with 8th bit on.
  #
  # GNU Readline will wait for the 2nd character with "keyseq-timeout"
  # milli-seconds but wait forever after 3rd characters.
  def read_io(keyseq_timeout, &block)
    buffer = []
    loop do
      c = Reline::IOGate.getc
      buffer << c
      result = @@key_stroke.match_status(buffer)
      case result
      when :matched
        block.(@@key_stroke.expand(buffer).map{ |c| Reline::Key.new(c, c, false) })
        break
      when :matching
        if buffer.size == 1
          begin
            succ_c = nil
            Timeout.timeout(keyseq_timeout / 1000.0) {
              succ_c = Reline::IOGate.getc
            }
          rescue Timeout::Error # cancel matching only when first byte
            block.([Reline::Key.new(c, c, false)])
            break
          else
            if @@key_stroke.match_status(buffer.dup.push(succ_c)) == :unmatched
              if c == "\e".ord
                block.([Reline::Key.new(succ_c, succ_c | 0b10000000, true)])
              else
                block.([Reline::Key.new(c, c, false), Reline::Key.new(succ_c, succ_c, false)])
              end
              break
            else
              Reline::IOGate.ungetc(succ_c)
            end
          end
        end
      when :unmatched
        if buffer.size == 1 and c == "\e".ord
          read_escaped_key(keyseq_timeout, buffer, block)
        else
          block.(buffer.map{ |c| Reline::Key.new(c, c, false) })
        end
        break
      end
    end
  end

  def read_escaped_key(keyseq_timeout, buffer, block)
    begin
      escaped_c = nil
      Timeout.timeout(keyseq_timeout / 1000.0) {
        escaped_c = Reline::IOGate.getc
      }
    rescue Timeout::Error # independent ESC
      block.([Reline::Key.new(c, c, false)])
    else
      if escaped_c.nil?
        block.([Reline::Key.new(c, c, false)])
      elsif escaped_c >= 128 # maybe, first byte of multi byte
        block.([Reline::Key.new(c, c, false), Reline::Key.new(escaped_c, escaped_c, false)])
      elsif escaped_c == "\e".ord # escape twice
        block.([Reline::Key.new(c, c, false), Reline::Key.new(c, c, false)])
      else
        block.([Reline::Key.new(escaped_c, escaped_c | 0b10000000, true)])
      end
    end
  end

  def may_req_ambiguous_char_width
    @@ambiguous_width = 2 if Reline::IOGate == Reline::GeneralIO or STDOUT.is_a?(File)
    return if @@ambiguous_width
    Reline::IOGate.move_cursor_column(0)
    print "\u{25bd}"
    @@ambiguous_width = Reline::IOGate.cursor_pos.x
    Reline::IOGate.move_cursor_column(0)
    Reline::IOGate.erase_after_cursor
  end

  def self.ambiguous_width
    @@ambiguous_width
  end
end

if Reline::IS_WINDOWS
  require 'reline/windows'
  Reline::IOGate = Reline::Windows
else
  require 'reline/ansi'
  Reline::IOGate = Reline::ANSI
end
require 'reline/general_io'
