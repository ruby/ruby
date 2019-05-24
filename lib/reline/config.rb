require 'pathname'

class Reline::Config
  DEFAULT_PATH = Pathname.new(Dir.home).join('.inputrc')

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
    @skip_section = nil
    @if_stack = []
    @editing_mode_label = :emacs
    @keymap_label = :emacs
    @key_actors = {}
    @key_actors[:emacs] = Reline::KeyActor::Emacs.new
    @key_actors[:vi_insert] = Reline::KeyActor::ViInsert.new
    @key_actors[:vi_command] = Reline::KeyActor::ViCommand.new
    @history_size = 500
    @keyseq_timeout = 500
  end

  def reset
    if editing_mode_is?(:vi_command)
      @editing_mode_label = :vi_insert
    end
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

  def read(file = DEFAULT_PATH)
    file = ENV['INPUTRC'] if ENV['INPUTRC']
    begin
      if file.respond_to?(:readlines)
        lines = file.readlines
      else
          File.open(file, 'rt') do |f|
            lines = f.readlines
          end
      end
    rescue Errno::ENOENT
      return nil
    end

    read_lines(lines)
    self
  end

  def read_lines(lines)
    lines.each do |line|
      line = line.chomp.gsub(/^\s*/, '')
      if line[0, 1] == '$'
        handle_directive(line[1..-1])
        next
      end

      next if @skip_section

      if line.match(/^set +([^ ]+) +([^ ]+)/i)
        var, value = $1.downcase, $2.downcase
        bind_variable(var, value)
        next
      end

      if line =~ /\s*(.*)\s*:\s*(.*)\s*$/
        key, func_name = $1, $2
        bind_key(key, func_name)
      end
    end
  end

  def handle_directive(directive)
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
      end
      unless @skip_section.nil?
        @if_stack << @skip_section
      end
      @skip_section = !condition
    when 'else'
      @skip_section = !@skip_section
    when 'endif'
      @skip_section = nil
      unless @if_stack.empty?
        @skip_section = @if_stack.pop
      end
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
    if key =~ /"(.*)"/
      keyseq = parse_keyseq($1).force_encoding('ASCII-8BIT')
    else
      keyseq = nil
    end
    if func_name =~ /"(.*)"/
      func = parse_keyseq($1).force_encoding('ASCII-8BIT')
    else
      func = func_name.to_sym # It must be macro.
    end
    [keyseq, func]
  end

  def key_notation_to_char(notation)
    case notation
    when /\\C-([A-Za-z_])/
      (1 + $1.downcase.ord - ?a.ord).chr('ASCII-8BIT')
    when /\\M-([0-9A-Za-z_])/
      modified_key = $1
      code =
        case $1
        when /[0-9]/
          ?\M-0.bytes.first + (modified_key.ord - ?0.ord)
        when /[A-Z]/
          ?\M-A.bytes.first + (modified_key.ord - ?A.ord)
        when /[a-z]/
          ?\M-a.bytes.first + (modified_key.ord - ?a.ord)
        end
      code.chr('ASCII-8BIT')
    when /\\C-M-[A-Za-z_]/, /\\M-C-[A-Za-z_]/
    # 129 M-^A
    when /\\(\d{1,3})/ then $1.to_i(8).chr # octal
    when /\\x(\h{1,2})/ then $1.to_i(16).chr # hexadecimal
    when "\\e" then ?\e
    when "\\\\" then ?\\
    when "\\\"" then ?"
    when "\\'" then ?'
    when "\\a" then ?\a
    when "\\b" then ?\b
    when "\\d" then ?\d
    when "\\f" then ?\f
    when "\\n" then ?\n
    when "\\r" then ?\r
    when "\\t" then ?\t
    when "\\v" then ?\v
    else notation
    end
  end

  def parse_keyseq(str)
    # TODO: Control- and Meta-
    ret = String.new(encoding: 'ASCII-8BIT')
    while str =~ /(\\C-[A-Za-z_]|\\M-[0-9A-Za-z_]|\\C-M-[A-Za-z_]|\\M-C-[A-Za-z_]|\\e|\\\\|\\"|\\'|\\a|\\b|\\d|\\f|\\n|\\r|\\t|\\v|\\\d{1,3}|\\x\h{1,2}|.)/
      ret << key_notation_to_char($&)
      str = $'
    end
    ret
  end
end
