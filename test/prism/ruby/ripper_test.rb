# frozen_string_literal: true

return if RUBY_VERSION < "3.3" || RUBY_ENGINE != "ruby"

require_relative "../test_helper"
require "ripper"

module Prism
  class RipperTest < TestCase
    # Skip these tests that Ripper is reporting the wrong results for.
    incorrect = [
      # Ripper incorrectly attributes the block to the keyword.
      "seattlerb/block_return.txt",
      "whitequark/return_block.txt",

      # Ripper cannot handle named capture groups in regular expressions.
      "regex.txt",

      # Ripper fails to understand some structures that span across heredocs.
      "spanning_heredoc.txt",

      # Ripper interprets circular keyword arguments as method calls.
      "3.4/circular_parameters.txt",

      # Ripper doesn't emit `args_add_block` when endless method is prefixed by modifier.
      "4.0/endless_methods_command_call.txt",

      # https://bugs.ruby-lang.org/issues/21168#note-5
      "command_method_call_2.txt",
    ]

    if RUBY_VERSION.start_with?("3.3.")
      incorrect += [
        "whitequark/lvar_injecting_match.txt",
        "seattlerb/parse_pattern_058.txt",
        "regex_char_width.txt",
      ]
    end

    if RUBY_VERSION.start_with?("4.")
      incorrect += [
        # https://bugs.ruby-lang.org/issues/21945
        "and_or_with_suffix.txt",
      ]
    end

    # https://bugs.ruby-lang.org/issues/21669
    incorrect << "4.1/void_value.txt"
    # https://bugs.ruby-lang.org/issues/19107
    incorrect << "4.1/trailing_comma_after_method_arguments.txt"

    # Skip these tests that we haven't implemented yet.
    omitted_sexp_raw = [
      "bom_leading_space.txt",
      "bom_spaces.txt",
      "dos_endings.txt",
      "heredocs_with_fake_newlines.txt",
      "heredocs_with_ignored_newlines.txt",
      "seattlerb/block_call_dot_op2_brace_block.txt",
      "seattlerb/block_command_operation_colon.txt",
      "seattlerb/block_command_operation_dot.txt",
      "seattlerb/heredoc__backslash_dos_format.txt",
      "seattlerb/heredoc_backslash_nl.txt",
      "seattlerb/heredoc_nested.txt",
      "seattlerb/heredoc_squiggly_blank_line_plus_interpolation.txt",
      "tilde_heredocs.txt",
      "unparser/corpus/semantic/dstr.txt",
      "whitequark/dedenting_heredoc.txt",
      "whitequark/parser_drops_truncated_parts_of_squiggly_heredoc.txt",
      "whitequark/parser_slash_slash_n_escaping_in_literals.txt",
      "whitequark/ruby_bug_18878.txt",
      "whitequark/send_block_chain_cmd.txt",
      "whitequark/slash_newline_in_heredocs.txt"
    ]

    omitted_lex = [
      "heredoc_with_escaped_newline_at_start.txt",
      "heredocs_with_fake_newlines.txt",
      "indented_file_end.txt",
      "spanning_heredoc_newlines.txt",
      "whitequark/dedenting_heredoc.txt",
      "whitequark/procarg0.txt",
    ]

    omitted_scan = [
      "bom_leading_space.txt",
      "bom_spaces.txt",
      "dos_endings.txt",
      "heredocs_with_fake_newlines.txt",
      "rescue_modifier.txt",
      "seattlerb/block_call_dot_op2_brace_block.txt",
      "seattlerb/block_command_operation_colon.txt",
      "seattlerb/block_command_operation_dot.txt",
      "seattlerb/case_in.txt",
      "seattlerb/heredoc__backslash_dos_format.txt",
      "seattlerb/heredoc_backslash_nl.txt",
      "seattlerb/heredoc_nested.txt",
      "seattlerb/heredoc_squiggly_blank_line_plus_interpolation.txt",
      "seattlerb/heredoc_squiggly_empty.txt",
      "seattlerb/masgn_command_call.txt",
      "seattlerb/messy_op_asgn_lineno.txt",
      "seattlerb/op_asgn_primary_colon_const_command_call.txt",
      "seattlerb/parse_pattern_076.txt",
      "seattlerb/pct_w_heredoc_interp_nested.txt",
      "tilde_heredocs.txt",
      "unparser/corpus/literal/assignment.txt",
      "unparser/corpus/literal/pattern.txt",
      "unparser/corpus/semantic/dstr.txt",
      "variables.txt",
      "whitequark/dedenting_heredoc.txt",
      "whitequark/masgn_nested.txt",
      "whitequark/newline_in_hash_argument.txt",
      "whitequark/numparam_ruby_bug_19025.txt",
      "whitequark/op_asgn_cmd.txt",
      "whitequark/parser_drops_truncated_parts_of_squiggly_heredoc.txt",
      "whitequark/parser_slash_slash_n_escaping_in_literals.txt",
      "whitequark/pattern_matching_nil_pattern.txt",
      "whitequark/ruby_bug_12402.txt",
      "whitequark/ruby_bug_18878.txt",
      "whitequark/send_block_chain_cmd.txt",
      "whitequark/slash_newline_in_heredocs.txt",
    ]

    Fixture.each_for_current_ruby(except: incorrect | omitted_sexp_raw) do |fixture|
      define_method("#{fixture.test_name}_sexp_raw") { assert_ripper_sexp_raw(fixture.read) }
    end

    Fixture.each_for_current_ruby(except: incorrect | omitted_lex) do |fixture|
      define_method("#{fixture.test_name}_lex") { assert_ripper_lex(fixture.read) }
    end

    def test_lex_ignored_missing_heredoc_end
      ["", "-", "~"].each do |type|
        source = "<<#{type}FOO\n"
        assert_ripper_lex(source)

        source = "<<#{type}'FOO'\n"
        assert_ripper_lex(source)
      end
    end

    UNSUPPORTED_EVENTS = %i[comma ignored_nl nl semicolon sp ignored_sp]
    # Events that are currently not emitted
    SUPPORTED_EVENTS = Translation::Ripper::EVENTS - UNSUPPORTED_EVENTS
    # Events that assert against their line/column
    CHECK_LOCATION_EVENTS = %i[kw op lbrace rbrace lbracket rbracket lparen rparen words_sep label_end]

    module Events
      attr_reader :events

      def initialize(...)
        super
        @events = []
      end

      SUPPORTED_EVENTS.each do |event|
        define_method(:"on_#{event}") do |*args|
          if CHECK_LOCATION_EVENTS.include?(event)
            @events << [event, lineno, column, *args]
          else
            @events << [event, *args]
          end
          super(*args)
        end
      end
    end

    class RipperEvents < Ripper
      include Events
    end

    class PrismEvents < Translation::Ripper
      include Events
    end

    class ObjectEvents < Translation::Ripper
      OBJECT = BasicObject.new
      SUPPORTED_EVENTS.each do |event|
        define_method(:"on_#{event}") { |*args| OBJECT }
      end
    end

    Fixture.each_for_current_ruby(except: incorrect | omitted_scan) do |fixture|
      define_method("#{fixture.test_name}_events") do
        source = fixture.read
        # Similar to test/ripper/assert_parse_files.rb in CRuby
        object_events = ObjectEvents.new(source)
        assert_nothing_raised { object_events.parse }

        ripper = RipperEvents.new(source, fixture.path)
        prism = PrismEvents.new(source, fixture.path)
        ripper.parse
        prism.parse
        # Check that the same events are emitted, regardless of order
        assert_equal(ripper.events.sort_by(&:inspect), prism.events.sort_by(&:inspect))
      end
    end

    def test_lexer
      lexer = Translation::Ripper::Lexer.new("foo")
      expected = [[1, 0], :on_ident, "foo", Translation::Ripper::EXPR_CMDARG]

      assert_equal([expected], lexer.lex)
      assert_equal(expected, lexer.parse[0].to_a)
      assert_equal(lexer.parse[0].to_a, lexer.scan[0].to_a)

      assert_equal(%i[on_int on_sp on_op], Translation::Ripper::Lexer.new("1 +").lex.map { |token| token[1] })
      assert_raise(SyntaxError) { Translation::Ripper::Lexer.new("1 +").lex(raise_errors: true) }
    end


    # On syntax invalid code the output doesn't always match up
    # In these cases we just want to make sure that it doesn't raise.
    def test_lex_invalid_syntax
      assert_nothing_raised do
        Translation::Ripper.lex('scan/\p{alpha}/')
      end

      assert_equal(Ripper.lex('if;)'), Translation::Ripper.lex('if;)'))
    end

    def test_tokenize
      source = "foo;1;BAZ"
      assert_equal(Ripper.tokenize(source), Translation::Ripper.tokenize(source))
    end

    def test_sexp_coercion
      string_like = Object.new
      def string_like.to_str
        "a"
      end
      assert_equal Ripper.sexp(string_like), Translation::Ripper.sexp(string_like)

      File.open(__FILE__) do |file1|
        File.open(__FILE__) do |file2|
          assert_equal Ripper.sexp(file1), Translation::Ripper.sexp(file2)
        end
      end

      File.open(__FILE__) do |file1|
        File.open(__FILE__) do |file2|
          object1_with_gets = Object.new
          object1_with_gets.define_singleton_method(:gets) do
            file1.gets
          end

          object2_with_gets = Object.new
          object2_with_gets.define_singleton_method(:gets) do
            file2.gets
          end

          assert_equal Ripper.sexp(object1_with_gets), Translation::Ripper.sexp(object2_with_gets)
        end
      end
    end

    def test_lex_coersion
      string_like = Object.new
      def string_like.to_str
        "a"
      end
      assert_equal Ripper.lex(string_like), Translation::Ripper.lex(string_like)
    end

    # Check that the hardcoded values don't change without us noticing.
    def test_internals
      actual = Translation::Ripper.constants.select { |name| name.start_with?("EXPR_") }.sort
      expected = Ripper.constants.select { |name| name.start_with?("EXPR_") }.sort

      assert_equal(expected, actual)
      expected.zip(actual).each do |ripper, prism|
        assert_equal(Ripper.const_get(ripper), Translation::Ripper.const_get(prism))
      end
    end

    private

    def assert_ripper_sexp_raw(source)
      assert_equal Ripper.sexp_raw(source), Prism::Translation::Ripper.sexp_raw(source)
    end

    def assert_ripper_lex(source)
      prism = Translation::Ripper.lex(source)
      ripper = Ripper.lex(source)

      # Prism emits tokens by their order in the code, not in parse order
      ripper.sort_by! { |elem| elem[0] }

      [prism.size, ripper.size].max.times do |index|
        expected = ripper[index]
        actual = prism[index]

        # There are some tokens that have slightly different state that do not
        # effect the parse tree, so they may not match.
        if expected && actual && expected[1] == actual[1] && %i[on_comment on_heredoc_end on_embexpr_end on_sp].include?(expected[1])
          expected[3] = actual[3] = nil
        end

        assert_equal(expected, actual)
      end
    end
  end
end
