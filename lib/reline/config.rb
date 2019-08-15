require 'pathname'

class Reline::Config
  attr_reader :test_mode

  DEFAULT_PATH = '~/.inputrc'

  KEYSEQ_PATTERN = /\\(?:C|Control)-[A-Za-z_]|\\(?:M|Meta)-[0-9A-Za-z_]|\\(?:C|Control)-(?:M|Meta)-[A-Za-z_]|\\(?:M|Meta)-(?:C|Control)-[A-Za-z_]|\\e|\\[\\\"\'abdfnrtv]|\\\d{1,3}|\\x\h{1,2}|./

  class InvalidInputrc < RuntimeError
    attr_accessor :file, :lineno
  end

  VARIABLE_NAMES = %w{
    bind-tty-special-chars
    blink-matching-paren
    byte-oriented
    completion-ignore-case
    convert-meta
    disable-completion
    enable-keypad
    expand-tilde
    history-preserve-point
    history-size
    horizontal-scroll-mode
    input-meta
    keyseq-timeout
    mark-directories
    mark-modified-lines
    mark-symlinked-directories
    match-hidden-files
    meta-flag
    output-meta
    page-completions
    prefer-visible-bell
    print-completions-horizontally
    show-all-if-ambiguous
    show-all-if-unmodified
    visible-stats
  }
  VARIABLE_NAME_SYMBOLS = VARIABLE_NAMES.map { |v| :"#{v.tr(?-, ?_)}" }
  VARIABLE_NAME_SYMBOLS.each do |v|
    attr_accessor v
  end

  def initialize
    @additional_key_bindings = {} # from inputrc
    @default_key_bindings = {} # environment-dependent
    @skip_section = nil
    @if_stack = nil
    @editing_mode_label = :emacs
    @keymap_label = :emacs
    @key_actors = {}
    @key_actors[:emacs] = Reline::KeyActor::Emacs.new
    @key_actors[:vi_insert] = Reline::KeyActor::ViInsert.new
    @key_actors[:vi_command] = Reline::KeyActor::ViCommand.new
    @history_size = 500
    @keyseq_timeout = 500
    @test_mode = false
  end

  def reset
    if editing_mode_is?(:vi_command)
      @editing_mode_label = :vi_insert
    end
    @additional_key_bindings = {}
    @default_key_bindings = {}
  end

  def editing_mode
    @key_actors[@editing_mode_label]
  end

  def editing_mode=(val)
    @editing_mode_label = val
  end

  def editing_mode_is?(*val)
    (val.respond_to?(:any?) ? val : [val]).any?(@editing_mode_label)
  end

  def keymap
    @key_actors[@keymap_label]
  end

  def read(file = nil)
    file ||= File.expand_path(ENV['INPUTRC'] || DEFAULT_PATH)
    begin
      if file.respond_to?(:readlines)
        lines = file.readlines
      else
        lines = File.readlines(file)
      end
    rescue Errno::ENOENT
      return nil
    end

    read_lines(lines, file)
    self
  rescue InvalidInputrc => e
    warn e.message
    nil
  end

  def key_bindings
    # override @default_key_bindings with @additional_key_bindings
    @default_key_bindings.merge(@additional_key_bindings)
  end

  def add_default_key_binding(keystroke, target)
    @default_key_bindings[keystroke] = target
  end

  def reset_default_key_bindings
    @default_key_bindings = {}
  end

  def read_lines(lines, file = nil)
    conditions = [@skip_section, @if_stack]
    @skip_section = nil
    @if_stack = []

    lines.each_with_index do |line, no|
      next if line.match(/\A\s*#/)

      no += 1

      line = line.chomp.lstrip
      if line.start_with?('$')
        handle_directive(line[1..-1], file, no)
        next
      end

      next if @skip_section

      case line
      when /^set +([^ ]+) +([^ ]+)/i
        var, value = $1.downcase, $2.downcase
        bind_variable(var, value)
        next
      when /\s*("#{KEYSEQ_PATTERN}+")\s*:\s*(.*)\s*$/o
        key, func_name = $1, $2
        keystroke, func = bind_key(key, func_name)
        next unless keystroke
        @additional_key_bindings[keystroke] = func
      end
    end
    unless @if_stack.empty?
      raise InvalidInputrc, "#{file}:#{@if_stack.last[1]}: unclosed if"
    end
  ensure
    @skip_section, @if_stack = conditions
  end

  def handle_directive(directive, file, no)
    directive, args = directive.split(' ')
    case directive
    when 'if'
      condition = false
      case args # TODO: variables
      when 'mode'
      when 'term'
      when 'version'
      else # application name
        condition = true if args == 'Ruby'
        condition = true if args == 'Reline'
      end
      @if_stack << [file, no, @skip_section]
      @skip_section = !condition
    when 'else'
      if @if_stack.empty?
        raise InvalidInputrc, "#{file}:#{no}: unmatched else"
      end
      @skip_section = !@skip_section
    when 'endif'
      if @if_stack.empty?
        raise InvalidInputrc, "#{file}:#{no}: unmatched endif"
      end
      @skip_section = @if_stack.pop
    when 'include'
      read(args)
    end
  end

  def bind_variable(name, value)
    case name
    when VARIABLE_NAMES then
      variable_name = :"@#{name.tr(?-, ?_)}"
      instance_variable_set(variable_name, value.nil? || value == '1' || value == 'on')
    when 'bell-style'
      @bell_style =
        case value
        when 'none', 'off'
          :none
        when 'audible', 'on'
          :audible
        when 'visible'
          :visible
        else
          :audible
        end
    when 'comment-begin'
      @comment_begin = value.dup
    when 'completion-query-items'
      @completion_query_items = value.to_i
    when 'isearch-terminators'
      @isearch_terminators = instance_eval(value)
    when 'editing-mode'
      case value
      when 'emacs'
        @editing_mode_label = :emacs
        @keymap_label = :emacs
      when 'vi'
        @editing_mode_label = :vi_insert
        @keymap_label = :vi_insert
      end
    when 'keymap'
      case value
      when 'emacs', 'emacs-standard', 'emacs-meta', 'emacs-ctlx'
        @keymap_label = :emacs
      when 'vi', 'vi-move', 'vi-command'
        @keymap_label = :vi_command
      when 'vi-insert'
        @keymap_label = :vi_insert
      end
    when 'keyseq-timeout'
      @keyseq_timeout = value.to_i
    end
  end

  def bind_key(key, func_name)
    if key =~ /\A"(.*)"\z/
      keyseq = parse_keyseq($1)
    else
      keyseq = nil
    end
    if func_name =~ /"(.*)"/
      func = parse_keyseq($1)
    else
      func = func_name.tr(?-, ?_).to_sym # It must be macro.
    end
    [keyseq, func]
  end

  def key_notation_to_code(notation)
    case notation
    when /\\(?:C|Control)-([A-Za-z_])/
      (1 + $1.downcase.ord - ?a.ord)
    when /\\(?:M|Meta)-([0-9A-Za-z_])/
      modified_key = $1
      case $1
      when /[0-9]/
        ?\M-0.bytes.first + (modified_key.ord - ?0.ord)
      when /[A-Z]/
        ?\M-A.bytes.first + (modified_key.ord - ?A.ord)
      when /[a-z]/
        ?\M-a.bytes.first + (modified_key.ord - ?a.ord)
      end
    when /\\(?:C|Control)-(?:M|Meta)-[A-Za-z_]/, /\\(?:M|Meta)-(?:C|Control)-[A-Za-z_]/
    # 129 M-^A
    when /\\(\d{1,3})/ then $1.to_i(8) # octal
    when /\\x(\h{1,2})/ then $1.to_i(16) # hexadecimal
    when "\\e" then ?\e.ord
    when "\\\\" then ?\\.ord
    when "\\\"" then ?".ord
    when "\\'" then ?'.ord
    when "\\a" then ?\a.ord
    when "\\b" then ?\b.ord
    when "\\d" then ?\d.ord
    when "\\f" then ?\f.ord
    when "\\n" then ?\n.ord
    when "\\r" then ?\r.ord
    when "\\t" then ?\t.ord
    when "\\v" then ?\v.ord
    else notation.ord
    end
  end

  def parse_keyseq(str)
    ret = []
    str.scan(KEYSEQ_PATTERN) do
      ret << key_notation_to_code($&)
    end
    ret
  end
end
