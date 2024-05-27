require 'io/console'
require 'forwardable'
require 'reline/version'
require 'reline/config'
require 'reline/key_actor'
require 'reline/key_stroke'
require 'reline/line_editor'
require 'reline/history'
require 'reline/terminfo'
require 'reline/face'
require 'rbconfig'

module Reline
  # NOTE: For making compatible with the rb-readline gem
  FILENAME_COMPLETION_PROC = nil
  USERNAME_COMPLETION_PROC = nil

  class ConfigEncodingConversionError < StandardError; end

  Key = Struct.new(:char, :combined_char, :with_meta) do
    def match?(other)
      case other
      when Reline::Key
        (other.char.nil? or char.nil? or char == other.char) and
        (other.combined_char.nil? or combined_char.nil? or combined_char == other.combined_char) and
        (other.with_meta.nil? or with_meta.nil? or with_meta == other.with_meta)
      when Integer, Symbol
        (combined_char and combined_char == other) or
        (combined_char.nil? and char and char == other)
      else
        false
      end
    end
    alias_method :==, :match?
  end
  CursorPos = Struct.new(:x, :y)
  DialogRenderInfo = Struct.new(
    :pos,
    :contents,
    :face,
    :bg_color, # For the time being, this line should stay here for the compatibility with IRB.
    :width,
    :height,
    :scrollbar,
    keyword_init: true
  )

  class Core
    ATTR_READER_NAMES = %i(
      completion_append_character
      basic_word_break_characters
      completer_word_break_characters
      basic_quote_characters
      completer_quote_characters
      filename_quote_characters
      special_prefixes
      completion_proc
      output_modifier_proc
      prompt_proc
      auto_indent_proc
      pre_input_hook
      dig_perfect_match_proc
    ).each(&method(:attr_reader))

    attr_accessor :config
    attr_accessor :key_stroke
    attr_accessor :line_editor
    attr_accessor :last_incremental_search
    attr_reader :output

    extend Forwardable
    def_delegators :config,
      :autocompletion,
      :autocompletion=

    def initialize
      self.output = STDOUT
      @mutex = Mutex.new
      @dialog_proc_list = {}
      yield self
      @completion_quote_character = nil
    end

    def io_gate
      Reline::IOGate
    end

    def encoding
      io_gate.encoding
    end

    def completion_append_character=(val)
      if val.nil?
        @completion_append_character = nil
      elsif val.size == 1
        @completion_append_character = val.encode(encoding)
      elsif val.size > 1
        @completion_append_character = val[0].encode(encoding)
      else
        @completion_append_character = nil
      end
    end

    def basic_word_break_characters=(v)
      @basic_word_break_characters = v.encode(encoding)
    end

    def completer_word_break_characters=(v)
      @completer_word_break_characters = v.encode(encoding)
    end

    def basic_quote_characters=(v)
      @basic_quote_characters = v.encode(encoding)
    end

    def completer_quote_characters=(v)
      @completer_quote_characters = v.encode(encoding)
    end

    def filename_quote_characters=(v)
      @filename_quote_characters = v.encode(encoding)
    end

    def special_prefixes=(v)
      @special_prefixes = v.encode(encoding)
    end

    def completion_case_fold=(v)
      @config.completion_ignore_case = v
    end

    def completion_case_fold
      @config.completion_ignore_case
    end

    def completion_quote_character
      @completion_quote_character
    end

    def completion_proc=(p)
      raise ArgumentError unless p.respond_to?(:call) or p.nil?
      @completion_proc = p
    end

    def output_modifier_proc=(p)
      raise ArgumentError unless p.respond_to?(:call) or p.nil?
      @output_modifier_proc = p
    end

    def prompt_proc=(p)
      raise ArgumentError unless p.respond_to?(:call) or p.nil?
      @prompt_proc = p
    end

    def auto_indent_proc=(p)
      raise ArgumentError unless p.respond_to?(:call) or p.nil?
      @auto_indent_proc = p
    end

    def pre_input_hook=(p)
      @pre_input_hook = p
    end

    def dig_perfect_match_proc=(p)
      raise ArgumentError unless p.respond_to?(:call) or p.nil?
      @dig_perfect_match_proc = p
    end

    DialogProc = Struct.new(:dialog_proc, :context)
    def add_dialog_proc(name_sym, p, context = nil)
      raise ArgumentError unless name_sym.instance_of?(Symbol)
      if p.nil?
        @dialog_proc_list.delete(name_sym)
      else
        raise ArgumentError unless p.respond_to?(:call)
        @dialog_proc_list[name_sym] = DialogProc.new(p, context)
      end
    end

    def dialog_proc(name_sym)
      @dialog_proc_list[name_sym]
    end

    def input=(val)
      raise TypeError unless val.respond_to?(:getc) or val.nil?
      if val.respond_to?(:getc) && io_gate.respond_to?(:input=)
        io_gate.input = val
      end
    end

    def output=(val)
      raise TypeError unless val.respond_to?(:write) or val.nil?
      @output = val
      if io_gate.respond_to?(:output=)
        io_gate.output = val
      end
    end

    def vi_editing_mode
      config.editing_mode = :vi_insert
      nil
    end

    def emacs_editing_mode
      config.editing_mode = :emacs
      nil
    end

    def vi_editing_mode?
      config.editing_mode_is?(:vi_insert, :vi_command)
    end

    def emacs_editing_mode?
      config.editing_mode_is?(:emacs)
    end

    def get_screen_size
      io_gate.get_screen_size
    end

    Reline::DEFAULT_DIALOG_PROC_AUTOCOMPLETE = ->() {
      # autocomplete
      return unless config.autocompletion

      journey_data = completion_journey_data
      return unless journey_data

      target = journey_data.list.first
      completed = journey_data.list[journey_data.pointer]
      result = journey_data.list.drop(1)
      pointer = journey_data.pointer - 1
      return if completed.empty? || (result == [completed] && pointer < 0)

      target_width = Reline::Unicode.calculate_width(target)
      completed_width = Reline::Unicode.calculate_width(completed)
      if cursor_pos.x <= completed_width - target_width
        # When target is rendered on the line above cursor position
        x = screen_width - completed_width
        y = -1
      else
        x = [cursor_pos.x - completed_width, 0].max
        y = 0
      end
      cursor_pos_to_render = Reline::CursorPos.new(x, y)
      if context and context.is_a?(Array)
        context.clear
        context.push(cursor_pos_to_render, result, pointer, dialog)
      end
      dialog.pointer = pointer
      DialogRenderInfo.new(
        pos: cursor_pos_to_render,
        contents: result,
        scrollbar: true,
        height: [15, preferred_dialog_height].min,
        face: :completion_dialog
      )
    }
    Reline::DEFAULT_DIALOG_CONTEXT = Array.new

    def readmultiline(prompt = '', add_hist = false, &confirm_multiline_termination)
      @mutex.synchronize do
        unless confirm_multiline_termination
          raise ArgumentError.new('#readmultiline needs block to confirm multiline termination')
        end

        Reline.update_iogate
        io_gate.with_raw_input do
          inner_readline(prompt, add_hist, true, &confirm_multiline_termination)
        end

        whole_buffer = line_editor.whole_buffer.dup
        whole_buffer.taint if RUBY_VERSION < '2.7'
        if add_hist and whole_buffer and whole_buffer.chomp("\n").size > 0
          Reline::HISTORY << whole_buffer
        end

        if line_editor.eof?
          line_editor.reset_line
          # Return nil if the input is aborted by C-d.
          nil
        else
          whole_buffer
        end
      end
    end

    def readline(prompt = '', add_hist = false)
      @mutex.synchronize do
        Reline.update_iogate
        io_gate.with_raw_input do
          inner_readline(prompt, add_hist, false)
        end

        line = line_editor.line.dup
        line.taint if RUBY_VERSION < '2.7'
        if add_hist and line and line.chomp("\n").size > 0
          Reline::HISTORY << line.chomp("\n")
        end

        line_editor.reset_line if line_editor.line.nil?
        line
      end
    end

    private def inner_readline(prompt, add_hist, multiline, &confirm_multiline_termination)
      if ENV['RELINE_STDERR_TTY']
        if io_gate.win?
          $stderr = File.open(ENV['RELINE_STDERR_TTY'], 'a')
        else
          $stderr.reopen(ENV['RELINE_STDERR_TTY'], 'w')
        end
        $stderr.sync = true
        $stderr.puts "Reline is used by #{Process.pid}"
      end
      unless config.test_mode or config.loaded?
        config.read
        io_gate.set_default_key_bindings(config)
      end
      otio = io_gate.prep

      may_req_ambiguous_char_width
      line_editor.reset(prompt, encoding: encoding)
      if multiline
        line_editor.multiline_on
        if block_given?
          line_editor.confirm_multiline_termination_proc = confirm_multiline_termination
        end
      else
        line_editor.multiline_off
      end
      line_editor.output = output
      line_editor.completion_proc = completion_proc
      line_editor.completion_append_character = completion_append_character
      line_editor.output_modifier_proc = output_modifier_proc
      line_editor.prompt_proc = prompt_proc
      line_editor.auto_indent_proc = auto_indent_proc
      line_editor.dig_perfect_match_proc = dig_perfect_match_proc
      pre_input_hook&.call
      unless Reline::IOGate == Reline::GeneralIO
        @dialog_proc_list.each_pair do |name_sym, d|
          line_editor.add_dialog_proc(name_sym, d.dialog_proc, d.context)
        end
      end

      line_editor.print_nomultiline_prompt(prompt)
      line_editor.update_dialogs
      line_editor.rerender

      begin
        line_editor.set_signal_handlers
        loop do
          read_io(config.keyseq_timeout) { |inputs|
            line_editor.set_pasting_state(io_gate.in_pasting?)
            inputs.each do |key|
              if key.char == :bracketed_paste_start
                text = io_gate.read_bracketed_paste
                line_editor.insert_pasted_text(text)
                line_editor.scroll_into_view
              else
                line_editor.update(key)
              end
            end
          }
          if line_editor.finished?
            line_editor.render_finished
            break
          else
            line_editor.set_pasting_state(io_gate.in_pasting?)
            line_editor.rerender
          end
        end
        io_gate.move_cursor_column(0)
      rescue Errno::EIO
        # Maybe the I/O has been closed.
      ensure
        line_editor.finalize
        io_gate.deprep(otio)
      end
    end

    # GNU Readline waits for "keyseq-timeout" milliseconds to see if the ESC
    # is followed by a character, and times out and treats it as a standalone
    # ESC if the second character does not arrive. If the second character
    # comes before timed out, it is treated as a modifier key with the
    # meta-property of meta-key, so that it can be distinguished from
    # multibyte characters with the 8th bit turned on.
    #
    # GNU Readline will wait for the 2nd character with "keyseq-timeout"
    # milli-seconds but wait forever after 3rd characters.
    private def read_io(keyseq_timeout, &block)
      buffer = []
      loop do
        c = io_gate.getc(Float::INFINITY)
        if c == -1
          result = :unmatched
        else
          buffer << c
          result = key_stroke.match_status(buffer)
        end
        case result
        when :matched
          expanded = key_stroke.expand(buffer).map{ |expanded_c|
            Reline::Key.new(expanded_c, expanded_c, false)
          }
          block.(expanded)
          break
        when :matching
          if buffer.size == 1
            case read_2nd_character_of_key_sequence(keyseq_timeout, buffer, c, block)
            when :break then break
            when :next  then next
            end
          end
        when :unmatched
          if buffer.size == 1 and c == "\e".ord
            read_escaped_key(keyseq_timeout, c, block)
          else
            expanded = buffer.map{ |expanded_c|
              Reline::Key.new(expanded_c, expanded_c, false)
            }
            block.(expanded)
          end
          break
        end
      end
    end

    private def read_2nd_character_of_key_sequence(keyseq_timeout, buffer, c, block)
      succ_c = io_gate.getc(keyseq_timeout.fdiv(1000))
      if succ_c
        case key_stroke.match_status(buffer.dup.push(succ_c))
        when :unmatched
          if c == "\e".ord
            block.([Reline::Key.new(succ_c, succ_c | 0b10000000, true)])
          else
            block.([Reline::Key.new(c, c, false), Reline::Key.new(succ_c, succ_c, false)])
          end
          return :break
        when :matching
          io_gate.ungetc(succ_c)
          return :next
        when :matched
          buffer << succ_c
          expanded = key_stroke.expand(buffer).map{ |expanded_c|
            Reline::Key.new(expanded_c, expanded_c, false)
          }
          block.(expanded)
          return :break
        end
      else
        block.([Reline::Key.new(c, c, false)])
        return :break
      end
    end

    private def read_escaped_key(keyseq_timeout, c, block)
      escaped_c = io_gate.getc(keyseq_timeout.fdiv(1000))

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

    def ambiguous_width
      may_req_ambiguous_char_width unless defined? @ambiguous_width
      @ambiguous_width
    end

    private def may_req_ambiguous_char_width
      @ambiguous_width = 2 if io_gate == Reline::GeneralIO or !STDOUT.tty?
      return if defined? @ambiguous_width
      io_gate.move_cursor_column(0)
      begin
        output.write "\u{25bd}"
      rescue Encoding::UndefinedConversionError
        # LANG=C
        @ambiguous_width = 1
      else
        @ambiguous_width = io_gate.cursor_pos.x
      end
      io_gate.move_cursor_column(0)
      io_gate.erase_after_cursor
    end
  end

  extend Forwardable
  extend SingleForwardable

  #--------------------------------------------------------
  # Documented API
  #--------------------------------------------------------

  (Core::ATTR_READER_NAMES).each { |name|
    def_single_delegators :core, :"#{name}", :"#{name}="
  }
  def_single_delegators :core, :input=, :output=
  def_single_delegators :core, :vi_editing_mode, :emacs_editing_mode
  def_single_delegators :core, :readline
  def_single_delegators :core, :completion_case_fold, :completion_case_fold=
  def_single_delegators :core, :completion_quote_character
  def_instance_delegators self, :readline
  private :readline


  #--------------------------------------------------------
  # Undocumented API
  #--------------------------------------------------------

  # Testable in original
  def_single_delegators :core, :get_screen_size
  def_single_delegators :line_editor, :eof?
  def_instance_delegators self, :eof?
  def_single_delegators :line_editor, :delete_text
  def_single_delegator :line_editor, :line, :line_buffer
  def_single_delegator :line_editor, :byte_pointer, :point
  def_single_delegator :line_editor, :byte_pointer=, :point=

  def self.insert_text(*args, &block)
    line_editor.insert_text(*args, &block)
    self
  end

  # Untestable in original
  def_single_delegator :line_editor, :rerender, :redisplay
  def_single_delegators :core, :vi_editing_mode?, :emacs_editing_mode?
  def_single_delegators :core, :ambiguous_width
  def_single_delegators :core, :last_incremental_search
  def_single_delegators :core, :last_incremental_search=
  def_single_delegators :core, :add_dialog_proc
  def_single_delegators :core, :dialog_proc
  def_single_delegators :core, :autocompletion, :autocompletion=

  def_single_delegators :core, :readmultiline
  def_instance_delegators self, :readmultiline
  private :readmultiline

  def self.encoding_system_needs
    self.core.encoding
  end

  def self.core
    @core ||= Core.new { |core|
      core.config = Reline::Config.new
      core.key_stroke = Reline::KeyStroke.new(core.config)
      core.line_editor = Reline::LineEditor.new(core.config, core.encoding)

      core.basic_word_break_characters = " \t\n`><=;|&{("
      core.completer_word_break_characters = " \t\n`><=;|&{("
      core.basic_quote_characters = '"\''
      core.completer_quote_characters = '"\''
      core.filename_quote_characters = ""
      core.special_prefixes = ""
      core.add_dialog_proc(:autocomplete, Reline::DEFAULT_DIALOG_PROC_AUTOCOMPLETE, Reline::DEFAULT_DIALOG_CONTEXT)
    }
  end

  def self.ungetc(c)
    core.io_gate.ungetc(c)
  end

  def self.line_editor
    core.line_editor
  end

  def self.update_iogate
    return if core.config.test_mode

    # Need to change IOGate when `$stdout.tty?` change from false to true by `$stdout.reopen`
    # Example: rails/spring boot the application in non-tty, then run console in tty.
    if ENV['TERM'] != 'dumb' && core.io_gate == Reline::GeneralIO && $stdout.tty?
      require 'reline/ansi'
      remove_const(:IOGate)
      const_set(:IOGate, Reline::ANSI)
    end
  end
end

require 'reline/general_io'
io = Reline::GeneralIO
unless ENV['TERM'] == 'dumb'
  case RbConfig::CONFIG['host_os']
  when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
    require 'reline/windows'
    tty = (io = Reline::Windows).msys_tty?
  else
    tty = $stdout.tty?
  end
end
Reline::IOGate = if tty
  require 'reline/ansi'
  Reline::ANSI
else
  io
end

Reline::Face.load_initial_configs

Reline::HISTORY = Reline::History.new(Reline.core.config)
