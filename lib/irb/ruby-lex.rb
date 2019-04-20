# frozen_string_literal: false
#
#   irb/ruby-lex.rb - ruby lexcal analyzer
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#

require "e2mmap"
require "ripper"

# :stopdoc:
class RubyLex

  extend Exception2MessageMapper
  def_exception(:TerminateLineInput, "Terminate Line Input")

  def initialize
    @exp_line_no = @line_no = 1
    @indent = 0
    @continue = false
    @line = ""
    @prompt = nil
  end

  # io functions
  def set_input(io, p = nil, &block)
    @io = io
    if @io.respond_to?(:check_termination)
      @io.check_termination do |code|
        @tokens = Ripper.lex(code)
        continue = process_continue
        code_block_open = check_code_block(code)
        indent = process_nesting_level
        ltype = process_literal_type
        if code_block_open or ltype or continue or indent > 0
          false
        else
          true
        end
      end
    end
    if p.respond_to?(:call)
      @input = p
    elsif block_given?
      @input = block
    else
      @input = Proc.new{@io.gets}
    end
  end

  def set_prompt(p = nil, &block)
    p = block if block_given?
    if p.respond_to?(:call)
      @prompt = p
    else
      @prompt = Proc.new{print p}
    end
  end

  def prompt
    if @prompt
      @prompt.call(@ltype, @indent, @continue, @line_no)
    end
  end

  def initialize_input
    @ltype = nil
    @indent = 0
    @continue = false
    @line = ""
    @exp_line_no = @line_no
    @code_block_open = false
  end

  def each_top_level_statement
    initialize_input
    catch(:TERM_INPUT) do
      loop do
        begin
          prompt
          unless l = lex
            throw :TERM_INPUT if @line == ''
          else
            @line_no += 1
            next if l == "\n"
            @line.concat l
            if @code_block_open or @ltype or @continue or @indent > 0
              next
            end
          end
          if @line != "\n"
            @line.force_encoding(@io.encoding)
            yield @line, @exp_line_no
          end
          break unless l
          @line = ''
          @exp_line_no = @line_no

          @indent = 0
        rescue TerminateLineInput
          initialize_input
          prompt
        end
      end
    end
  end

  def lex
    line = @input.call
    if @io.respond_to?(:check_termination)
      return line # multiline
    end
    code = @line + (line.nil? ? '' : line)
    code.gsub!(/\n*$/, '').concat("\n")
    @tokens = Ripper.lex(code)
    @continue = process_continue
    @code_block_open = check_code_block(code)
    @indent = process_nesting_level
    @ltype = process_literal_type
    line
  end

  def process_continue
    continued_bits = Ripper::EXPR_BEG | Ripper::EXPR_FNAME | Ripper::EXPR_DOT
    # last token is always newline
    if @tokens.size >= 2 and @tokens[-2][1] == :on_regexp_end
      # end of regexp literal
      return false
    elsif @tokens.size >= 2 and @tokens[-2][1] == :on_semicolon
      return false
    elsif @tokens.size >= 2 and @tokens[-2][1] == :on_kw and (@tokens[-2][2] == 'begin' or @tokens[-2][2] == 'else')
      return false
    elsif !@tokens.empty? and @tokens.last[2] == "\\\n"
      return true
    elsif @tokens.size >= 2 and @tokens[-2][3].anybits?(continued_bits)
      # end of literal except for regexp
      return true
    end
    false
  end

  def check_code_block(code)
    return true if @tokens.empty?
    if @tokens.last[1] == :on_heredoc_beg
      return true
    end

    begin # check if parser error are available
      RubyVM::InstructionSequence.compile(code)
    rescue SyntaxError => e
      case e.message
      when /unterminated (?:string|regexp) meets end of file/
        # "unterminated regexp meets end of file"
        #
        #   example:
        #     /
        #
        # "unterminated string meets end of file"
        #
        #   example:
        #     '
        return true
      when /syntax error, unexpected end-of-input/
        # "syntax error, unexpected end-of-input, expecting keyword_end"
        #
        #   example:
        #     if ture
        #       hoge
        #       if false
        #         fuga
        #       end
        return true
      when /syntax error, unexpected keyword_end/
        # "syntax error, unexpected keyword_end"
        #
        #   example:
        #     if (
        #     end
        #
        #   example:
        #     end
        return false
      when /unexpected tREGEXP_BEG/
        # "syntax error, unexpected tREGEXP_BEG, expecting keyword_do or '{' or '('"
        #
        #   example:
        #     method / f /
        return false
      end
    end

    last_lex_state = @tokens.last[3]
    if last_lex_state.allbits?(Ripper::EXPR_BEG)
      return false
    elsif last_lex_state.allbits?(Ripper::EXPR_DOT)
      return true
    elsif last_lex_state.allbits?(Ripper::EXPR_CLASS)
      return true
    elsif last_lex_state.allbits?(Ripper::EXPR_FNAME)
      return true
    elsif last_lex_state.allbits?(Ripper::EXPR_VALUE)
      return true
    elsif last_lex_state.allbits?(Ripper::EXPR_ARG)
      return false
    end

    false
  end

  def process_nesting_level
    @tokens.inject(0) { |indent, t|
      case t[1]
      when :on_lbracket, :on_lbrace, :on_lparen
        indent += 1
      when :on_rbracket, :on_rbrace, :on_rparen
        indent -= 1
      when :on_kw
        case t[2]
        when 'def', 'do', 'case', 'for', 'begin', 'class', 'module'
          indent += 1
        when 'if', 'unless', 'while', 'until', 'rescue'
          # postfix if/unless/while/until/rescue must be Ripper::EXPR_LABEL
          indent += 1 unless t[3].allbits?(Ripper::EXPR_LABEL)
        when 'end'
          indent -= 1
        end
      end
      # percent literals are not indented
      indent
    }
  end

  def check_string_literal
    i = 0
    start_token = []
    end_type = []
    while i < @tokens.size
      t = @tokens[i]
      case t[1]
      when :on_tstring_beg
        start_token << t
        end_type << :on_tstring_end
      when :on_regexp_beg
        start_token << t
        end_type << :on_regexp_end
      when :on_symbeg
        if (i + 1) < @tokens.size and @tokens[i + 1][1] != :on_ident
          start_token << t
          end_type << :on_tstring_end
        end
      when :on_backtick
        start_token << t
        end_type << :on_tstring_end
      when :on_qwords_beg, :on_words_beg, :on_qsymbols_beg, :on_symbols_beg
        start_token << t
        end_type << :on_tstring_end
      when :on_heredoc_beg
        start_token << t
        end_type << :on_heredoc_end
      when end_type.last
        start_token.pop
        end_type.pop
      end
      i += 1
    end
    start_token.last.nil? ? '' : start_token.last
  end

  def process_literal_type
    start_token = check_string_literal
    case start_token[1]
    when :on_tstring_beg
      case start_token[2]
      when ?"      then ?"
      when /^%.$/  then ?"
      when /^%Q.$/ then ?"
      when ?'      then ?'
      when /^%q.$/ then ?'
      end
    when :on_regexp_beg   then ?/
    when :on_symbeg       then ?:
    when :on_backtick     then ?`
    when :on_qwords_beg   then ?]
    when :on_words_beg    then ?]
    when :on_qsymbols_beg then ?]
    when :on_symbols_beg  then ?]
    when :on_heredoc_beg
      start_token[2] =~ /<<[-~]?(['"`])[_a-zA-Z0-9]+\1/
      case $1
      when ?" then ?"
      when ?' then ?'
      when ?` then ?`
      else         ?"
      end
    else
      nil
    end
  end
end
# :startdoc:
