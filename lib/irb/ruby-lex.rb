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

require "ripper"
require "jruby" if RUBY_ENGINE == "jruby"

# :stopdoc:
class RubyLex

  class TerminateLineInput < StandardError
    def initialize
      super("Terminate Line Input")
    end
  end

  def initialize
    @exp_line_no = @line_no = 1
    @indent = 0
    @continue = false
    @line = ""
    @prompt = nil
  end

  def self.compile_with_errors_suppressed(code)
    line_no = 1
    begin
      result = yield code, line_no
    rescue ArgumentError
      code = ";\n#{code}"
      line_no = 0
      result = yield code, line_no
    end
    result
  end

  # io functions
  def set_input(io, p = nil, &block)
    @io = io
    if @io.respond_to?(:check_termination)
      @io.check_termination do |code|
        code.gsub!(/\s*\z/, '').concat("\n")
        ltype, indent, continue, code_block_open = check_state(code)
        if ltype or indent > 0 or continue or code_block_open
          false
        else
          true
        end
      end
    end
    if @io.respond_to?(:dynamic_prompt)
      @io.dynamic_prompt do |lines|
        lines << '' if lines.empty?
        result = []
        lines.each_index { |i|
          c = lines[0..i].map{ |l| l + "\n" }.join
          ltype, indent, continue, code_block_open = check_state(c)
          result << @prompt.call(ltype, indent, continue || code_block_open, @line_no + i)
        }
        result
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

  def ripper_lex_without_warning(code)
    verbose, $VERBOSE = $VERBOSE, nil
    tokens = nil
    self.class.compile_with_errors_suppressed(code) do |inner_code, line_no|
      tokens = Ripper.lex(inner_code, '-', line_no)
    end
    $VERBOSE = verbose
    tokens
  end

  def set_auto_indent(context)
    if @io.respond_to?(:auto_indent) and context.auto_indent_mode
      @io.auto_indent do |lines, line_index, byte_pointer, is_newline|
        if is_newline
          md = lines[line_index - 1].match(/(\A +)/)
          prev_spaces = md.nil? ? 0 : md[1].count(' ')
          @tokens = ripper_lex_without_warning(lines[0..line_index].join("\n"))
          depth_difference = check_newline_depth_difference
          prev_spaces + depth_difference * 2
        else
          code = line_index.zero? ? '' : lines[0..(line_index - 1)].map{ |l| l + "\n" }.join
          last_line = lines[line_index]&.byteslice(0, byte_pointer)
          code += last_line if last_line
          @tokens = ripper_lex_without_warning(code)
          corresponding_token_depth = check_corresponding_token_depth
          if corresponding_token_depth
            corresponding_token_depth
          else
            nil
          end
        end
      end
    end
  end

  def check_state(code)
    @tokens = ripper_lex_without_warning(code)
    ltype = process_literal_type
    indent = process_nesting_level
    continue = process_continue
    code_block_open = check_code_block(code)
    [ltype, indent, continue, code_block_open]
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
            @line_no += l.count("\n")
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
          break if @io.eof?
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
    code.gsub!(/\s*\z/, '').concat("\n")
    @tokens = ripper_lex_without_warning(code)
    @continue = process_continue
    @code_block_open = check_code_block(code)
    @indent = process_nesting_level
    @ltype = process_literal_type
    line
  end

  def process_continue
    # last token is always newline
    if @tokens.size >= 2 and @tokens[-2][1] == :on_regexp_end
      # end of regexp literal
      return false
    elsif @tokens.size >= 2 and @tokens[-2][1] == :on_semicolon
      return false
    elsif @tokens.size >= 2 and @tokens[-2][1] == :on_kw and ['begin', 'else', 'ensure'].include?(@tokens[-2][2])
      return false
    elsif !@tokens.empty? and @tokens.last[2] == "\\\n"
      return true
    elsif @tokens.size >= 1 and @tokens[-1][1] == :on_heredoc_end # "EOH\n"
      return false
    elsif @tokens.size >= 2 and defined?(Ripper::EXPR_BEG) and @tokens[-2][3].anybits?(Ripper::EXPR_BEG | Ripper::EXPR_FNAME)
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
      verbose, $VERBOSE = $VERBOSE, nil
      case RUBY_ENGINE
      when 'jruby'
        JRuby.compile_ir(code)
      else
        self.class.compile_with_errors_suppressed(code) do |inner_code, line_no|
          RubyVM::InstructionSequence.compile(inner_code, nil, nil, line_no)
        end
      end
    rescue EncodingError
      # This is for a hash with invalid encoding symbol, {"\xAE": 1}
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
      when /syntax error, unexpected '\.'/
        # "syntax error, unexpected '.'"
        #
        #   example:
        #     .
        return false
      when /unexpected tREGEXP_BEG/
        # "syntax error, unexpected tREGEXP_BEG, expecting keyword_do or '{' or '('"
        #
        #   example:
        #     method / f /
        return false
      end
    ensure
      $VERBOSE = verbose
    end

    if defined?(Ripper::EXPR_BEG)
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
    end

    false
  end

  def process_nesting_level
    indent = 0
    in_oneliner_def = nil
    @tokens.each_with_index { |t, index|
      # detecting one-liner method definition
      if in_oneliner_def.nil?
        if t[3].allbits?(Ripper::EXPR_ENDFN)
          in_oneliner_def = :ENDFN
        end
      else
        if t[3].allbits?(Ripper::EXPR_ENDFN)
          # continuing
        elsif t[3].allbits?(Ripper::EXPR_BEG)
          if t[2] == '='
            in_oneliner_def = :BODY
          end
        elsif t[3].allbits?(Ripper::EXPR_END)
          if in_oneliner_def == :BODY
            # one-liner method definition
            indent -= 1
          end
          in_oneliner_def = nil
        else
          in_oneliner_def = nil
        end
      end

      case t[1]
      when :on_lbracket, :on_lbrace, :on_lparen, :on_tlambeg
        indent += 1
      when :on_rbracket, :on_rbrace, :on_rparen
        indent -= 1
      when :on_kw
        next if index > 0 and @tokens[index - 1][3].allbits?(Ripper::EXPR_FNAME)
        case t[2]
        when 'do'
          if index > 0 and @tokens[index - 1][3].anybits?(Ripper::EXPR_CMDARG | Ripper::EXPR_ENDFN | Ripper::EXPR_ARG)
            # method_with_block do; end
            indent += 1
          else
            # while cond do; end # also "until" or "for"
            # This "do" doesn't increment indent because "while" already
            # incremented.
          end
        when 'def', 'case', 'for', 'begin', 'class', 'module'
          indent += 1
        when 'if', 'unless', 'while', 'until'
          # postfix if/unless/while/until must be Ripper::EXPR_LABEL
          indent += 1 unless t[3].allbits?(Ripper::EXPR_LABEL)
        when 'end'
          indent -= 1
        end
      end
      # percent literals are not indented
    }
    indent
  end

  def check_newline_depth_difference
    depth_difference = 0
    open_brace_on_line = 0
    in_oneliner_def = nil
    @tokens.each_with_index do |t, index|
      # detecting one-liner method definition
      if in_oneliner_def.nil?
        if t[3].allbits?(Ripper::EXPR_ENDFN)
          in_oneliner_def = :ENDFN
        end
      else
        if t[3].allbits?(Ripper::EXPR_ENDFN)
          # continuing
        elsif t[3].allbits?(Ripper::EXPR_BEG)
          if t[2] == '='
            in_oneliner_def = :BODY
          end
        elsif t[3].allbits?(Ripper::EXPR_END)
          if in_oneliner_def == :BODY
            # one[-liner method definition
            depth_difference -= 1
          end
          in_oneliner_def = nil
        else
          in_oneliner_def = nil
        end
      end

      case t[1]
      when :on_ignored_nl, :on_nl, :on_comment
        if index != (@tokens.size - 1)
          depth_difference = 0
          open_brace_on_line = 0
        end
        next
      when :on_sp
        next
      end
      case t[1]
      when :on_lbracket, :on_lbrace, :on_lparen, :on_tlambeg
        depth_difference += 1
        open_brace_on_line += 1
      when :on_rbracket, :on_rbrace, :on_rparen
        depth_difference -= 1 if open_brace_on_line > 0
      when :on_kw
        next if index > 0 and @tokens[index - 1][3].allbits?(Ripper::EXPR_FNAME)
        case t[2]
        when 'do'
          if index > 0 and @tokens[index - 1][3].anybits?(Ripper::EXPR_CMDARG | Ripper::EXPR_ENDFN | Ripper::EXPR_ARG)
            # method_with_block do; end
            depth_difference += 1
          else
            # while cond do; end # also "until" or "for"
            # This "do" doesn't increment indent because "while" already
            # incremented.
          end
        when 'def', 'case', 'for', 'begin', 'class', 'module'
          depth_difference += 1
        when 'if', 'unless', 'while', 'until', 'rescue'
          # postfix if/unless/while/until/rescue must be Ripper::EXPR_LABEL
          unless t[3].allbits?(Ripper::EXPR_LABEL)
            depth_difference += 1
          end
        when 'else', 'elsif', 'ensure', 'when', 'in'
          depth_difference += 1
        end
      end
    end
    depth_difference
  end

  def check_corresponding_token_depth
    corresponding_token_depth = nil
    is_first_spaces_of_line = true
    is_first_printable_of_line = true
    spaces_of_nest = []
    spaces_at_line_head = 0
    open_brace_on_line = 0
    in_oneliner_def = nil
    @tokens.each_with_index do |t, index|
      # detecting one-liner method definition
      if in_oneliner_def.nil?
        if t[3].allbits?(Ripper::EXPR_ENDFN)
          in_oneliner_def = :ENDFN
        end
      else
        if t[3].allbits?(Ripper::EXPR_ENDFN)
          # continuing
        elsif t[3].allbits?(Ripper::EXPR_BEG)
          if t[2] == '='
            in_oneliner_def = :BODY
          end
        elsif t[3].allbits?(Ripper::EXPR_END)
          if in_oneliner_def == :BODY
            # one-liner method definition
            if is_first_printable_of_line
              corresponding_token_depth = spaces_of_nest.pop
            else
              spaces_of_nest.pop
              corresponding_token_depth = nil
            end
          end
          in_oneliner_def = nil
        else
          in_oneliner_def = nil
        end
      end

      case t[1]
      when :on_ignored_nl, :on_nl, :on_comment
        corresponding_token_depth = nil
        spaces_at_line_head = 0
        is_first_spaces_of_line = true
        is_first_printable_of_line = true
        open_brace_on_line = 0
        next
      when :on_sp
        spaces_at_line_head = t[2].count(' ') if is_first_spaces_of_line
        is_first_spaces_of_line = false
        next
      end
      case t[1]
      when :on_lbracket, :on_lbrace, :on_lparen, :on_tlambeg
        spaces_of_nest.push(spaces_at_line_head + open_brace_on_line * 2)
        open_brace_on_line += 1
      when :on_rbracket, :on_rbrace, :on_rparen
        if is_first_printable_of_line
          corresponding_token_depth = spaces_of_nest.pop
        else
          spaces_of_nest.pop
          corresponding_token_depth = nil
        end
        open_brace_on_line -= 1
      when :on_kw
        next if index > 0 and @tokens[index - 1][3].allbits?(Ripper::EXPR_FNAME)
        case t[2]
        when 'def', 'do', 'case', 'for', 'begin', 'class', 'module'
          spaces_of_nest.push(spaces_at_line_head)
        when 'rescue'
          unless t[3].allbits?(Ripper::EXPR_LABEL)
            corresponding_token_depth = spaces_of_nest.last
          end
        when 'if', 'unless', 'while', 'until'
          # postfix if/unless/while/until must be Ripper::EXPR_LABEL
          unless t[3].allbits?(Ripper::EXPR_LABEL)
            spaces_of_nest.push(spaces_at_line_head)
          end
        when 'else', 'elsif', 'ensure', 'when', 'in'
          corresponding_token_depth = spaces_of_nest.last
        when 'end'
          if is_first_printable_of_line
            corresponding_token_depth = spaces_of_nest.pop
          else
            spaces_of_nest.pop
            corresponding_token_depth = nil
          end
        end
      end
      is_first_spaces_of_line = false
      is_first_printable_of_line = false
    end
    corresponding_token_depth
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
        end_type << [:on_tstring_end, :on_label_end]
      when :on_regexp_beg
        start_token << t
        end_type << :on_regexp_end
      when :on_symbeg
        acceptable_single_tokens = %i{on_ident on_const on_op on_cvar on_ivar on_gvar on_kw}
        if (i + 1) < @tokens.size and acceptable_single_tokens.all?{ |t| @tokens[i + 1][1] != t }
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
      when *end_type.last
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
