require 'io/console'
require 'reline/version'
require 'reline/config'
require 'reline/key_actor'
require 'reline/key_stroke'
require 'reline/line_editor'

module Reline
  extend self
  FILENAME_COMPLETION_PROC = nil
  USERNAME_COMPLETION_PROC = nil
  HISTORY = Array.new

  if RUBY_PLATFORM =~ /mswin|mingw/
    IS_WINDOWS = true
  else
    IS_WINDOWS = false
  end

  CursorPos = Struct.new(:x, :y)

  class << self
    attr_accessor :basic_quote_characters
    attr_accessor :completer_quote_characters
    attr_accessor :completer_word_break_characters
    attr_reader :completion_append_character
    attr_accessor :completion_case_fold
    attr_accessor :filename_quote_characters
    attr_writer :input
    attr_writer :output
  end

  @@config = Reline::Config.new
  @@config.read
  @@line_editor = Reline::LineEditor.new(@@config)
  @@ambiguous_width = nil

  @basic_quote_characters = '"\''
  # TODO implement below
  #@completer_quote_characters
  #@completion_append_character
  #@completion_case_fold
  #@filename_quote_characters
  def self.completion_append_character=(val)
    if val.nil?
      @completion_append_character = nil
    elsif val.size == 1
      @completion_append_character = val
    elsif val.size > 1
      @completion_append_character = val[0]
    else
      @completion_append_character = val
    end
  end

  @@basic_word_break_characters = " \t\n`><=;|&{("
  def self.basic_word_break_characters
    @@basic_word_break_characters
  end
  def self.basic_word_break_characters=(v)
    @@basic_word_break_characters = v
  end

  @@completer_word_break_characters = @@basic_word_break_characters.dup

  @@completion_proc = nil
  def self.completion_proc
    @@completion_proc
  end
  def self.completion_proc=(p)
    @@completion_proc = p
  end

  @@dig_perfect_match_proc = nil
  def self.dig_perfect_match_proc
    @@dig_perfect_match_proc
  end
  def self.dig_perfect_match_proc=(p)
    @@dig_perfect_match_proc = p
  end

  def self.delete_text(start = nil, length = nil)
    raise NotImplementedError
  end

  if IS_WINDOWS
    require 'reline/windows'
  else
    require 'reline/ansi'
  end

  def retrieve_completion_block(line, byte_pointer)
    break_regexp = /[#{Regexp.escape(@@basic_word_break_characters)}]/
    before_pointer = line.byteslice(0, byte_pointer)
    break_point = before_pointer.rindex(break_regexp)
    if break_point
      preposing = before_pointer[0..(break_point)]
      block = before_pointer[(break_point + 1)..-1]
    else
      preposing = ''
      block = before_pointer
    end
    postposing = line.byteslice(byte_pointer, line.bytesize)
    [preposing, block, postposing]
  end

  def readmultiline(prompt = '', add_hist = false, &confirm_multiline_termination)
    if block_given?
      inner_readline(prompt, add_hist, true, &confirm_multiline_termination)
    else
      inner_readline(prompt, add_hist, true)
    end

    whole_buffer = @@line_editor.whole_buffer.dup
    whole_buffer.taint
    if add_hist and whole_buffer and whole_buffer.chomp.size > 0
      Reline::HISTORY << whole_buffer
    end

    whole_buffer
  end

  def readline(prompt = '', add_hist = false)
    inner_readline(prompt, add_hist, false)

    line = @@line_editor.line.dup
    line.taint
    if add_hist and line and line.chomp.size > 0
      Reline::HISTORY << line.chomp
    end

    line
  end

  def inner_readline(prompt, add_hist, multiline, &confirm_multiline_termination)
    otio = prep

    may_req_ambiguous_char_width
    if multiline
      @@line_editor.multiline_on
      if block_given?
        @@line_editor.confirm_multiline_termination_proc = confirm_multiline_termination
      end
    else
      @@line_editor.multiline_off
    end
    @@line_editor.completion_proc = @@completion_proc
    @@line_editor.dig_perfect_match_proc = @@dig_perfect_match_proc
    @@line_editor.retrieve_completion_block = method(:retrieve_completion_block)
    @@line_editor.rerender

    if IS_WINDOWS
      config = {
        key_mapping: {
          [224, 72] => :ed_prev_history,    # ↑
          [224, 80] => :ed_next_history,    # ↓
          [224, 77] => :ed_next_char,       # →
          [224, 75] => :ed_prev_char        # ←
        }
      }
    else
      config = {
        key_mapping: {
          [27, 91, 65] => :ed_prev_history,    # ↑
          [27, 91, 66] => :ed_next_history,    # ↓
          [27, 91, 67] => :ed_next_char,       # →
          [27, 91, 68] => :ed_prev_char        # ←
        }
      }
    end

    key_stroke = Reline::KeyStroke.new(config)
    begin
      while c = getc
        key_stroke.input_to!(c)&.then { |inputs|
          inputs.each { |c|
            @@line_editor.input_key(c)
            @@line_editor.rerender
          }
        }
        break if @@line_editor.finished?
      end
      Reline.move_cursor_column(0)
    rescue StandardError => e
      deprep(otio)
      raise e
    end

    deprep(otio)
  end

  def may_req_ambiguous_char_width
    return if @@ambiguous_width
    Reline.move_cursor_column(0)
    print "\u{25bd}"
    @@ambiguous_width = Reline.cursor_pos.x
    Reline.move_cursor_column(0)
    Reline.erase_after_cursor
  end

  def self.ambiguous_width
    @@ambiguous_width
  end
end
