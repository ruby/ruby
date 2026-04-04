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

    # Events that are currently not emitted
    UNSUPPORTED_EVENTS = %i[comma ignored_nl label_end lbrace lbracket lparen nl op rbrace rbracket rparen semicolon sp words_sep ignored_sp]
    SUPPORTED_EVENTS = Translation::Ripper::EVENTS - UNSUPPORTED_EVENTS
    # Events that assert against their line/column
    CHECK_LOCATION_EVENTS = %i[kw]
    IGNORE_FOR_SORT_EVENTS = %i[
      stmts_new stmts_add bodystmt void_stmt
      args_new args_add args_add_star args_add_block arg_paren method_add_arg
      mlhs_new mlhs_add_star
      word_new words_new symbols_new qwords_new qsymbols_new xstring_new regexp_new
      words_add symbols_add qwords_add qsymbols_add
      regexp_end tstring_end heredoc_end
      call command fcall vcall
      field aref_field var_field var_ref block_var ident params
      string_content heredoc_dedent unary binary dyna_symbol
      comment magic_comment embdoc embdoc_beg embdoc_end arg_ambiguous
    ]
    SORT_IGNORE = {
      aref: [
        "blocks.txt",
        "command_method_call.txt",
        "whitequark/ruby_bug_13547.txt",
      ],
      assoc_new: [
        "case_in_hash_key.txt",
        "whitequark/parser_bug_525.txt",
        "whitequark/ruby_bug_11380.txt",
      ],
      bare_assoc_hash: [
        "case_in_hash_key.txt",
        "method_calls.txt",
        "whitequark/parser_bug_525.txt",
        "whitequark/ruby_bug_11380.txt",
      ],
      brace_block: [
        "super.txt",
        "unparser/corpus/literal/super.txt"
      ],
      command_call: [
        "blocks.txt",
        "case_in_hash_key.txt",
        "seattlerb/block_call_dot_op2_cmd_args_do_block.txt",
        "seattlerb/block_call_operation_colon.txt",
        "seattlerb/block_call_operation_dot.txt",
      ],
      const_path_field: [
        "seattlerb/const_2_op_asgn_or2.txt",
        "seattlerb/const_op_asgn_or.txt",
        "whitequark/const_op_asgn.txt",
      ],
      const_path_ref: ["unparser/corpus/literal/defs.txt"],
      do_block: ["whitequark/super_block.txt"],
      embexpr_end: ["seattlerb/str_interp_ternary_or_label.txt"],
      rest_param: ["whitequark/send_lambda.txt"],
      top_const_field: [
        "seattlerb/const_3_op_asgn_or.txt",
        "seattlerb/const_op_asgn_and1.txt",
        "seattlerb/const_op_asgn_and2.txt",
        "whitequark/const_op_asgn.txt",
      ],
      mlhs_paren: ["unparser/corpus/literal/for.txt"],
      mlhs_add: [
        "whitequark/for_mlhs.txt",
      ],
      kw: [
        "defined.txt",
        "for.txt",
        "seattlerb/block_kw__required.txt",
        "seattlerb/case_in_42.txt",
        "seattlerb/case_in_67.txt",
        "seattlerb/case_in_86_2.txt",
        "seattlerb/case_in_86.txt",
        "seattlerb/case_in_hash_pat_paren_true.txt",
        "seattlerb/flip2_env_lvar.txt",
        "unless.txt",
        "unparser/corpus/semantic/and.txt",
        "whitequark/class.txt",
        "whitequark/find_pattern.txt",
        "whitequark/pattern_matching_hash.txt",
        "whitequark/pattern_matching_implicit_array_match.txt",
        "whitequark/pattern_matching_ranges.txt",
        "whitequark/super_block.txt",
        "write_command_operator.txt",
      ],
    }
    SORT_IGNORE.default = []
    SORT_EVENTS = SUPPORTED_EVENTS - IGNORE_FOR_SORT_EVENTS

    module Events
      attr_reader :events

      def initialize(...)
        super
        @events = []
      end

      def sorted_events
        @events.select do |e,|
          next false if e == :kw && @events.any? { |e,| e == :if_mod || e == :while_mod || e == :until_mod || e == :rescue || e == :rescue_mod || e == :while || e == :ensure }
          SORT_EVENTS.include?(e) && !SORT_IGNORE[e].include?(filename)
        end
      end

      SUPPORTED_EVENTS.each do |event|
        define_method(:"on_#{event}") do |*args|
          if CHECK_LOCATION_EVENTS.include?(event)
            @events << [event, lineno, column, *args.map(&:to_s)]
          else
            @events << [event, *args.map(&:to_s)]
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
        assert_equal(ripper.events.sort, prism.events.sort)
        # Check a subset of events against the correct order
        assert_equal(ripper.sorted_events, prism.sorted_events)
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
