# frozen_string_literal: false
#
#   irb/ruby-lex.rb - ruby lexcal analyzer
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
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

  def initialize(context)
    @context = context
    @exp_line_no = @line_no = 1
    @indent = 0
    @continue = false
    @line = ""
    @prompt = nil
  end

  def self.compile_with_errors_suppressed(code, line_no: 1)
    begin
      result = yield code, line_no
    rescue ArgumentError
      # Ruby can issue an error for the code if there is an
      # incomplete magic comment for encoding in it. Force an
      # expression with a new line before the code in this
      # case to prevent magic comment handling.  To make sure
      # line numbers in the lexed code remain the same,
      # decrease the line number by one.
      code = ";\n#{code}"
      line_no -= 1
      result = yield code, line_no
    end
    result
  end

  # io functions
  def set_input(io, &block)
    @io = io
    if @io.respond_to?(:check_termination)
      @io.check_termination do |code|
        if Reline::IOGate.in_pasting?
          lex = RubyLex.new(@context)
          rest = lex.check_termination_in_prev_line(code)
          if rest
            Reline.delete_text
            rest.bytes.reverse_each do |c|
              Reline.ungetc(c)
            end
            true
          else
            false
          end
        else
          # Accept any single-line input for symbol aliases or commands that transform args
          command = code.split(/\s/, 2).first
          if @context.symbol_alias?(command) || @context.transform_args?(command)
            next true
          end

          code.gsub!(/\s*\z/, '').concat("\n")
          tokens = self.class.ripper_lex_without_warning(code, context: @context)
          ltype, indent, continue, code_block_open = check_state(code, tokens)
          if ltype or indent > 0 or continue or code_block_open
            false
          else
            true
          end
        end
      end
    end
    if @io.respond_to?(:dynamic_prompt)
      @io.dynamic_prompt do |lines|
        lines << '' if lines.empty?
        result = []
        tokens = self.class.ripper_lex_without_warning(lines.map{ |l| l + "\n" }.join, context: @context)
        code = String.new
        partial_tokens = []
        unprocessed_tokens = []
        line_num_offset = 0
        tokens.each do |t|
          partial_tokens << t
          unprocessed_tokens << t
          if t.tok.include?("\n")
            t_str = t.tok
            t_str.each_line("\n") do |s|
              code << s
              next unless s.include?("\n")
              ltype, indent, continue, code_block_open = check_state(code, partial_tokens)
              result << @prompt.call(ltype, indent, continue || code_block_open, @line_no + line_num_offset)
              line_num_offset += 1
            end
            unprocessed_tokens = []
          else
            code << t.tok
          end
        end

        unless unprocessed_tokens.empty?
          ltype, indent, continue, code_block_open = check_state(code, unprocessed_tokens)
          result << @prompt.call(ltype, indent, continue || code_block_open, @line_no + line_num_offset)
        end
        result
      end
    end

    if block_given?
      @input = block
    else
      @input = Proc.new{@io.gets}
    end
  end

  def set_prompt(&block)
    @prompt = block
  end

  ERROR_TOKENS = [
    :on_parse_error,
    :compile_error,
    :on_assign_error,
    :on_alias_error,
    :on_class_name_error,
    :on_param_error
  ]

  def self.generate_local_variables_assign_code(local_variables)
    "#{local_variables.join('=')}=nil;" unless local_variables.empty?
  end

  def self.ripper_lex_without_warning(code, context: nil)
    verbose, $VERBOSE = $VERBOSE, nil
    lvars_code = generate_local_variables_assign_code(context&.local_variables || [])
    if lvars_code
      code = "#{lvars_code}\n#{code}"
      line_no = 0
    else
      line_no = 1
    end

    compile_with_errors_suppressed(code, line_no: line_no) do |inner_code, line_no|
      lexer = Ripper::Lexer.new(inner_code, '-', line_no)
      lexer.scan.each_with_object([]) do |t, tokens|
        next if t.pos.first == 0
        prev_tk = tokens.last
        position_overlapped = prev_tk && t.pos[0] == prev_tk.pos[0] && t.pos[1] < prev_tk.pos[1] + prev_tk.tok.bytesize
        if position_overlapped
          tokens[-1] = t if ERROR_TOKENS.include?(prev_tk.event) && !ERROR_TOKENS.include?(t.event)
        else
          tokens << t
        end
      end
    end
  ensure
    $VERBOSE = verbose
  end

  def find_prev_spaces(line_index)
    return 0 if @tokens.size == 0
    md = @tokens[0].tok.match(/(\A +)/)
    prev_spaces = md.nil? ? 0 : md[1].count(' ')
    line_count = 0
    @tokens.each_with_index do |t, i|
      if t.tok.include?("\n")
        line_count += t.tok.count("\n")
        if line_count >= line_index
          return prev_spaces
        end
        next if t.event == :on_tstring_content || t.event == :on_words_sep
        if (@tokens.size - 1) > i
          md = @tokens[i + 1].tok.match(/(\A +)/)
          prev_spaces = md.nil? ? 0 : md[1].count(' ')
        end
      end
    end
    prev_spaces
  end

  def set_auto_indent
    if @io.respond_to?(:auto_indent) and @context.auto_indent_mode
      @io.auto_indent do |lines, line_index, byte_pointer, is_newline|
        if is_newline
          @tokens = self.class.ripper_lex_without_warning(lines[0..line_index].join("\n"), context: @context)
          prev_spaces = find_prev_spaces(line_index)
          depth_difference = check_newline_depth_difference
          depth_difference = 0 if depth_difference < 0
          prev_spaces + depth_difference * 2
        else
          code = line_index.zero? ? '' : lines[0..(line_index - 1)].map{ |l| l + "\n" }.join
          last_line = lines[line_index]&.byteslice(0, byte_pointer)
          code += last_line if last_line
          @tokens = self.class.ripper_lex_without_warning(code, context: @context)
          check_corresponding_token_depth(lines, line_index)
        end
      end
    end
  end

  def check_state(code, tokens)
    ltype = process_literal_type(tokens)
    indent = process_nesting_level(tokens)
    continue = process_continue(tokens)
    lvars_code = self.class.generate_local_variables_assign_code(@context.local_variables)
    code = "#{lvars_code}\n#{code}" if lvars_code
    code_block_open = check_code_block(code, tokens)
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
            if l == "\n"
              @exp_line_no += 1
              next
            end
            @line.concat l
            if @code_block_open or @ltype or @continue or @indent > 0
              next
            end
          end
          if @line != "\n"
            @line.force_encoding(@io.encoding)
            yield @line, @exp_line_no
          end
          raise TerminateLineInput if @io.eof?
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
    @tokens = self.class.ripper_lex_without_warning(code, context: @context)
    @ltype, @indent, @continue, @code_block_open = check_state(code, @tokens)
    line
  end

  def process_continue(tokens)
    # last token is always newline
    if tokens.size >= 2 and tokens[-2].event == :on_regexp_end
      # end of regexp literal
      return false
    elsif tokens.size >= 2 and tokens[-2].event == :on_semicolon
      return false
    elsif tokens.size >= 2 and tokens[-2].event == :on_kw and ['begin', 'else', 'ensure'].include?(tokens[-2].tok)
      return false
    elsif !tokens.empty? and tokens.last.tok == "\\\n"
      return true
    elsif tokens.size >= 1 and tokens[-1].event == :on_heredoc_end # "EOH\n"
      return false
    elsif tokens.size >= 2 and tokens[-2].state.anybits?(Ripper::EXPR_BEG | Ripper::EXPR_FNAME) and tokens[-2].tok !~ /\A\.\.\.?\z/
      # end of literal except for regexp
      # endless range at end of line is not a continue
      return true
    end
    false
  end

  def check_code_block(code, tokens)
    return true if tokens.empty?
    if tokens.last.event == :on_heredoc_beg
      return true
    end

    begin # check if parser error are available
      verbose, $VERBOSE = $VERBOSE, nil
      case RUBY_ENGINE
      when 'ruby'
        self.class.compile_with_errors_suppressed(code) do |inner_code, line_no|
          RubyVM::InstructionSequence.compile(inner_code, nil, nil, line_no)
        end
      when 'jruby'
        JRuby.compile_ir(code)
      else
        catch(:valid) do
          eval("BEGIN { throw :valid, true }\n#{code}")
          false
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
        #     if true
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

    last_lex_state = tokens.last.state

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

  def process_nesting_level(tokens)
    indent = 0
    in_oneliner_def = nil
    tokens.each_with_index { |t, index|
      # detecting one-liner method definition
      if in_oneliner_def.nil?
        if t.state.allbits?(Ripper::EXPR_ENDFN)
          in_oneliner_def = :ENDFN
        end
      else
        if t.state.allbits?(Ripper::EXPR_ENDFN)
          # continuing
        elsif t.state.allbits?(Ripper::EXPR_BEG)
          if t.tok == '='
            in_oneliner_def = :BODY
          end
        else
          if in_oneliner_def == :BODY
            # one-liner method definition
            indent -= 1
          end
          in_oneliner_def = nil
        end
      end

      case t.event
      when :on_lbracket, :on_lbrace, :on_lparen, :on_tlambeg
        indent += 1
      when :on_rbracket, :on_rbrace, :on_rparen
        indent -= 1
      when :on_kw
        next if index > 0 and tokens[index - 1].state.allbits?(Ripper::EXPR_FNAME)
        case t.tok
        when 'do'
          syntax_of_do = take_corresponding_syntax_to_kw_do(tokens, index)
          indent += 1 if syntax_of_do == :method_calling
        when 'def', 'case', 'for', 'begin', 'class', 'module'
          indent += 1
        when 'if', 'unless', 'while', 'until'
          # postfix if/unless/while/until must be Ripper::EXPR_LABEL
          indent += 1 unless t.state.allbits?(Ripper::EXPR_LABEL)
        when 'end'
          indent -= 1
        end
      end
      # percent literals are not indented
    }
    indent
  end

  def is_method_calling?(tokens, index)
    tk = tokens[index]
    if tk.state.anybits?(Ripper::EXPR_CMDARG) and tk.event == :on_ident
      # The target method call to pass the block with "do".
      return true
    elsif tk.state.anybits?(Ripper::EXPR_ARG) and tk.event == :on_ident
      non_sp_index = tokens[0..(index - 1)].rindex{ |t| t.event != :on_sp }
      if non_sp_index
        prev_tk = tokens[non_sp_index]
        if prev_tk.state.anybits?(Ripper::EXPR_DOT) and prev_tk.event == :on_period
          # The target method call with receiver to pass the block with "do".
          return true
        end
      end
    end
    false
  end

  def take_corresponding_syntax_to_kw_do(tokens, index)
    syntax_of_do = nil
    # Finding a syntax corresponding to "do".
    index.downto(0) do |i|
      tk = tokens[i]
      # In "continue", the token isn't the corresponding syntax to "do".
      non_sp_index = tokens[0..(i - 1)].rindex{ |t| t.event != :on_sp }
      first_in_fomula = false
      if non_sp_index.nil?
        first_in_fomula = true
      elsif [:on_ignored_nl, :on_nl, :on_comment].include?(tokens[non_sp_index].event)
        first_in_fomula = true
      end
      if is_method_calling?(tokens, i)
        syntax_of_do = :method_calling
        break if first_in_fomula
      elsif tk.event == :on_kw && %w{while until for}.include?(tk.tok)
        # A loop syntax in front of "do" found.
        #
        #   while cond do # also "until" or "for"
        #   end
        #
        # This "do" doesn't increment indent because the loop syntax already
        # incremented.
        syntax_of_do = :loop_syntax
        break if first_in_fomula
      end
    end
    syntax_of_do
  end

  def is_the_in_correspond_to_a_for(tokens, index)
    syntax_of_in = nil
    # Finding a syntax corresponding to "do".
    index.downto(0) do |i|
      tk = tokens[i]
      # In "continue", the token isn't the corresponding syntax to "do".
      non_sp_index = tokens[0..(i - 1)].rindex{ |t| t.event != :on_sp }
      first_in_fomula = false
      if non_sp_index.nil?
        first_in_fomula = true
      elsif [:on_ignored_nl, :on_nl, :on_comment].include?(tokens[non_sp_index].event)
        first_in_fomula = true
      end
      if tk.event == :on_kw && tk.tok == 'for'
        # A loop syntax in front of "do" found.
        #
        #   while cond do # also "until" or "for"
        #   end
        #
        # This "do" doesn't increment indent because the loop syntax already
        # incremented.
        syntax_of_in = :for
      end
      break if first_in_fomula
    end
    syntax_of_in
  end

  def check_newline_depth_difference
    depth_difference = 0
    open_brace_on_line = 0
    in_oneliner_def = nil
    @tokens.each_with_index do |t, index|
      # detecting one-liner method definition
      if in_oneliner_def.nil?
        if t.state.allbits?(Ripper::EXPR_ENDFN)
          in_oneliner_def = :ENDFN
        end
      else
        if t.state.allbits?(Ripper::EXPR_ENDFN)
          # continuing
        elsif t.state.allbits?(Ripper::EXPR_BEG)
          if t.tok == '='
            in_oneliner_def = :BODY
          end
        else
          if in_oneliner_def == :BODY
            # one-liner method definition
            depth_difference -= 1
          end
          in_oneliner_def = nil
        end
      end

      case t.event
      when :on_ignored_nl, :on_nl, :on_comment
        if index != (@tokens.size - 1) and in_oneliner_def != :BODY
          depth_difference = 0
          open_brace_on_line = 0
        end
        next
      when :on_sp
        next
      end

      case t.event
      when :on_lbracket, :on_lbrace, :on_lparen, :on_tlambeg
        depth_difference += 1
        open_brace_on_line += 1
      when :on_rbracket, :on_rbrace, :on_rparen
        depth_difference -= 1 if open_brace_on_line > 0
      when :on_kw
        next if index > 0 and @tokens[index - 1].state.allbits?(Ripper::EXPR_FNAME)
        case t.tok
        when 'do'
          syntax_of_do = take_corresponding_syntax_to_kw_do(@tokens, index)
          depth_difference += 1 if syntax_of_do == :method_calling
        when 'def', 'case', 'for', 'begin', 'class', 'module'
          depth_difference += 1
        when 'if', 'unless', 'while', 'until', 'rescue'
          # postfix if/unless/while/until/rescue must be Ripper::EXPR_LABEL
          unless t.state.allbits?(Ripper::EXPR_LABEL)
            depth_difference += 1
          end
        when 'else', 'elsif', 'ensure', 'when'
          depth_difference += 1
        when 'in'
          unless is_the_in_correspond_to_a_for(@tokens, index)
            depth_difference += 1
          end
        when 'end'
          depth_difference -= 1
        end
      end
    end
    depth_difference
  end

  def check_corresponding_token_depth(lines, line_index)
    corresponding_token_depth = nil
    is_first_spaces_of_line = true
    is_first_printable_of_line = true
    spaces_of_nest = []
    spaces_at_line_head = 0
    open_brace_on_line = 0
    in_oneliner_def = nil

    if heredoc_scope?
      return lines[line_index][/^ */].length
    end

    @tokens.each_with_index do |t, index|
      # detecting one-liner method definition
      if in_oneliner_def.nil?
        if t.state.allbits?(Ripper::EXPR_ENDFN)
          in_oneliner_def = :ENDFN
        end
      else
        if t.state.allbits?(Ripper::EXPR_ENDFN)
          # continuing
        elsif t.state.allbits?(Ripper::EXPR_BEG)
          if t.tok == '='
            in_oneliner_def = :BODY
          end
        else
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
        end
      end

      case t.event
      when :on_ignored_nl, :on_nl, :on_comment, :on_heredoc_end, :on_embdoc_end
        if in_oneliner_def != :BODY
          corresponding_token_depth = nil
          spaces_at_line_head = 0
          is_first_spaces_of_line = true
          is_first_printable_of_line = true
          open_brace_on_line = 0
        end
        next
      when :on_sp
        spaces_at_line_head = t.tok.count(' ') if is_first_spaces_of_line
        is_first_spaces_of_line = false
        next
      end

      case t.event
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
        next if index > 0 and @tokens[index - 1].state.allbits?(Ripper::EXPR_FNAME)
        case t.tok
        when 'do'
          syntax_of_do = take_corresponding_syntax_to_kw_do(@tokens, index)
          if syntax_of_do == :method_calling
            spaces_of_nest.push(spaces_at_line_head)
          end
        when 'def', 'case', 'for', 'begin', 'class', 'module'
          spaces_of_nest.push(spaces_at_line_head)
        when 'rescue'
          unless t.state.allbits?(Ripper::EXPR_LABEL)
            corresponding_token_depth = spaces_of_nest.last
          end
        when 'if', 'unless', 'while', 'until'
          # postfix if/unless/while/until must be Ripper::EXPR_LABEL
          unless t.state.allbits?(Ripper::EXPR_LABEL)
            spaces_of_nest.push(spaces_at_line_head)
          end
        when 'else', 'elsif', 'ensure', 'when'
          corresponding_token_depth = spaces_of_nest.last
        when 'in'
          if in_keyword_case_scope?
            corresponding_token_depth = spaces_of_nest.last
          end
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

  def check_string_literal(tokens)
    i = 0
    start_token = []
    end_type = []
    pending_heredocs = []
    while i < tokens.size
      t = tokens[i]
      case t.event
      when *end_type.last
        start_token.pop
        end_type.pop
      when :on_tstring_beg
        start_token << t
        end_type << [:on_tstring_end, :on_label_end]
      when :on_regexp_beg
        start_token << t
        end_type << :on_regexp_end
      when :on_symbeg
        acceptable_single_tokens = %i{on_ident on_const on_op on_cvar on_ivar on_gvar on_kw on_int on_backtick}
        if (i + 1) < tokens.size
          if acceptable_single_tokens.all?{ |st| tokens[i + 1].event != st }
            start_token << t
            end_type << :on_tstring_end
          else
            i += 1
          end
        end
      when :on_backtick
        if t.state.allbits?(Ripper::EXPR_BEG)
          start_token << t
          end_type << :on_tstring_end
        end
      when :on_qwords_beg, :on_words_beg, :on_qsymbols_beg, :on_symbols_beg
        start_token << t
        end_type << :on_tstring_end
      when :on_heredoc_beg
        pending_heredocs << t
      end

      if pending_heredocs.any? && t.tok.include?("\n")
        pending_heredocs.reverse_each do |t|
          start_token << t
          end_type << :on_heredoc_end
        end
        pending_heredocs = []
      end
      i += 1
    end
    pending_heredocs.first || start_token.last
  end

  def process_literal_type(tokens)
    start_token = check_string_literal(tokens)
    return nil if start_token == ""

    case start_token&.event
    when :on_tstring_beg
      case start_token&.tok
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
      start_token&.tok =~ /<<[-~]?(['"`])\w+\1/
      $1 || ?"
    else
      nil
    end
  end

  def check_termination_in_prev_line(code)
    tokens = self.class.ripper_lex_without_warning(code, context: @context)
    past_first_newline = false
    index = tokens.rindex do |t|
      # traverse first token before last line
      if past_first_newline
        if t.tok.include?("\n")
          true
        end
      elsif t.tok.include?("\n")
        past_first_newline = true
        false
      else
        false
      end
    end

    if index
      first_token = nil
      last_line_tokens = tokens[(index + 1)..(tokens.size - 1)]
      last_line_tokens.each do |t|
        unless [:on_sp, :on_ignored_sp, :on_comment].include?(t.event)
          first_token = t
          break
        end
      end

      if first_token.nil?
        return false
      elsif first_token && first_token.state == Ripper::EXPR_DOT
        return false
      else
        tokens_without_last_line = tokens[0..index]
        ltype = process_literal_type(tokens_without_last_line)
        indent = process_nesting_level(tokens_without_last_line)
        continue = process_continue(tokens_without_last_line)
        code_block_open = check_code_block(tokens_without_last_line.map(&:tok).join(''), tokens_without_last_line)
        if ltype or indent > 0 or continue or code_block_open
          return false
        else
          return last_line_tokens.map(&:tok).join('')
        end
      end
    end
    false
  end

  private

  def heredoc_scope?
    heredoc_tokens = @tokens.select { |t| [:on_heredoc_beg, :on_heredoc_end].include?(t.event) }
    heredoc_tokens[-1]&.event == :on_heredoc_beg
  end

  def in_keyword_case_scope?
    kw_tokens = @tokens.select { |t| t.event == :on_kw && ['case', 'for', 'end'].include?(t.tok) }
    counter = 0
    kw_tokens.reverse.each do |t|
      if t.tok == 'case'
        return true if counter.zero?
        counter += 1
      elsif t.tok == 'for'
        counter += 1
      elsif t.tok == 'end'
        counter -= 1
      end
    end
    false
  end
end
# :startdoc:
