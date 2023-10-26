# frozen_string_literal: true
require "irb"

require_relative "helper"

module TestIRB
  class RubyLexTest < TestCase
    def setup
      save_encodings
    end

    def teardown
      restore_encodings
    end

    def test_interpolate_token_with_heredoc_and_unclosed_embexpr
      code = <<~'EOC'
        ①+<<A-②
        #{③*<<B/④
        #{⑤&<<C|⑥
      EOC
      ripper_tokens = Ripper.tokenize(code)
      rubylex_tokens = IRB::RubyLex.ripper_lex_without_warning(code)
      # Assert no missing part
      assert_equal(code, rubylex_tokens.map(&:tok).join)
      # Assert ripper tokens are not removed
      ripper_tokens.each do |tok|
        assert(rubylex_tokens.any? { |t| t.tok == tok && t.tok != :on_ignored_by_ripper })
      end
      # Assert interpolated token position
      rubylex_tokens.each do |t|
        row, col = t.pos
        assert_equal t.tok, code.lines[row - 1].byteslice(col, t.tok.bytesize)
      end
    end

    def test_local_variables_dependent_code
      lines = ["a /1#/ do", "2"]
      assert_indent_level(lines, 1)
      assert_code_block_open(lines, true)
      assert_indent_level(lines, 0, local_variables: ['a'])
      assert_code_block_open(lines, false, local_variables: ['a'])
    end

    def test_literal_ends_with_space
      assert_code_block_open(['% a'], true)
      assert_code_block_open(['% a '], false)
    end

    def test_literal_ends_with_newline
      assert_code_block_open(['%'], true)
      assert_code_block_open(['%', ''], false)
    end

    def test_should_continue
      assert_should_continue(['a'], false)
      assert_should_continue(['/a/'], false)
      assert_should_continue(['a;'], false)
      assert_should_continue(['<<A', 'A'], false)
      assert_should_continue(['a...'], false)
      assert_should_continue(['a\\'], true)
      assert_should_continue(['a.'], true)
      assert_should_continue(['a+'], true)
      assert_should_continue(['a; #comment', '', '=begin', 'embdoc', '=end', ''], false)
      assert_should_continue(['a+ #comment', '', '=begin', 'embdoc', '=end', ''], true)
    end

    def test_code_block_open_with_should_continue
      # syntax ok
      assert_code_block_open(['a'], false) # continue: false
      assert_code_block_open(['a\\'], true) # continue: true

      # recoverable syntax error code is not terminated
      assert_code_block_open(['a+'], true)

      # unrecoverable syntax error code is terminated
      assert_code_block_open(['.; a+'], false)

      # other syntax error that failed to determine if it is recoverable or not
      assert_code_block_open(['@; a'], false)
      assert_code_block_open(['@; a+'], true)
      assert_code_block_open(['@; (a'], true)
    end

    def test_broken_percent_literal
      tokens = IRB::RubyLex.ripper_lex_without_warning('%wwww')
      pos_to_index = {}
      tokens.each_with_index { |t, i|
        assert_nil(pos_to_index[t.pos], "There is already another token in the position of #{t.inspect}.")
        pos_to_index[t.pos] = i
      }
    end

    def test_broken_percent_literal_in_method
      tokens = IRB::RubyLex.ripper_lex_without_warning(<<~EOC.chomp)
        def foo
          %wwww
        end
      EOC
      pos_to_index = {}
      tokens.each_with_index { |t, i|
        assert_nil(pos_to_index[t.pos], "There is already another token in the position of #{t.inspect}.")
        pos_to_index[t.pos] = i
      }
    end

    def test_unterminated_code
      ['do', '<<A'].each do |code|
        tokens = IRB::RubyLex.ripper_lex_without_warning(code)
        assert_equal(code, tokens.map(&:tok).join, "Cannot reconstruct code from tokens")
        error_tokens = tokens.map(&:event).grep(/error/)
        assert_empty(error_tokens, 'Error tokens must be ignored if there is corresponding non-error token')
      end
    end

    def test_unterminated_heredoc_string_literal
      ['<<A;<<B', "<<A;<<B\n", "%W[\#{<<A;<<B", "%W[\#{<<A;<<B\n"].each do |code|
        tokens = IRB::RubyLex.ripper_lex_without_warning(code)
        string_literal = IRB::NestingParser.open_tokens(tokens).last
        assert_equal('<<A', string_literal&.tok)
      end
    end

    def test_indent_level_with_heredoc_and_embdoc
      reference_code = <<~EOC.chomp
        if true
          hello
          p(
          )
      EOC
      code_with_heredoc = <<~EOC.chomp
        if true
          <<~A
          A
          p(
          )
      EOC
      code_with_embdoc = <<~EOC.chomp
        if true
        =begin
        =end
          p(
          )
      EOC
      expected = 1
      assert_indent_level(reference_code.lines, expected)
      assert_indent_level(code_with_heredoc.lines, expected)
      assert_indent_level(code_with_embdoc.lines, expected)
    end

    def test_assignment_expression
      ruby_lex = IRB::RubyLex.new

      [
        "foo = bar",
        "@foo = bar",
        "$foo = bar",
        "@@foo = bar",
        "::Foo = bar",
        "a::Foo = bar",
        "Foo = bar",
        "foo.bar = 1",
        "foo[1] = bar",
        "foo += bar",
        "foo -= bar",
        "foo ||= bar",
        "foo &&= bar",
        "foo, bar = 1, 2",
        "foo.bar=(1)",
        "foo; foo = bar",
        "foo; foo = bar; ;\n ;",
        "foo\nfoo = bar",
      ].each do |exp|
        assert(
          ruby_lex.assignment_expression?(exp, local_variables: []),
          "#{exp.inspect}: should be an assignment expression"
        )
      end

      [
        "foo",
        "foo.bar",
        "foo[0]",
        "foo = bar; foo",
        "foo = bar\nfoo",
      ].each do |exp|
        refute(
          ruby_lex.assignment_expression?(exp, local_variables: []),
          "#{exp.inspect}: should not be an assignment expression"
        )
      end
    end

    def test_assignment_expression_with_local_variable
      ruby_lex = IRB::RubyLex.new
      code = "a /1;x=1#/"
      refute(ruby_lex.assignment_expression?(code, local_variables: []), "#{code}: should not be an assignment expression")
      assert(ruby_lex.assignment_expression?(code, local_variables: [:a]), "#{code}: should be an assignment expression")
      refute(ruby_lex.assignment_expression?("", local_variables: [:a]), "empty code should not be an assignment expression")
    end

    def test_initialising_the_old_top_level_ruby_lex
      assert_in_out_err(["--disable-gems", "-W:deprecated"], <<~RUBY, [], /warning: constant ::RubyLex is deprecated/)
        require "irb"
        ::RubyLex.new(nil)
      RUBY
    end

    private

    def assert_indent_level(lines, expected, local_variables: [])
      indent_level, _continue, _code_block_open = check_state(lines, local_variables: local_variables)
      error_message = "Calculated the wrong number of indent level for:\n #{lines.join("\n")}"
      assert_equal(expected, indent_level, error_message)
    end

    def assert_should_continue(lines, expected, local_variables: [])
      _indent_level, continue, _code_block_open = check_state(lines, local_variables: local_variables)
      error_message = "Wrong result of should_continue for:\n #{lines.join("\n")}"
      assert_equal(expected, continue, error_message)
    end

    def assert_code_block_open(lines, expected, local_variables: [])
      _indent_level, _continue, code_block_open = check_state(lines, local_variables: local_variables)
      error_message = "Wrong result of code_block_open for:\n #{lines.join("\n")}"
      assert_equal(expected, code_block_open, error_message)
    end

    def check_state(lines, local_variables: [])
      code = lines.map { |l| "#{l}\n" }.join # code should end with "\n"
      ruby_lex = IRB::RubyLex.new
      tokens, opens, terminated = ruby_lex.check_code_state(code, local_variables: local_variables)
      indent_level = ruby_lex.calc_indent_level(opens)
      continue = ruby_lex.should_continue?(tokens)
      [indent_level, continue, !terminated]
    end
  end
end
