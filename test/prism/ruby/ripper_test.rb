# frozen_string_literal: true

return if RUBY_VERSION < "3.3" || RUBY_ENGINE != "ruby"

require_relative "../test_helper"
require "ripper"

module Ruby::Prism
  class RipperTest < TestCase
    # Skip these tests that Ripper is reporting the wrong results for.
    incorrect = [
      # Ripper incorrectly attributes the block to the keyword.
      "seattlerb/block_return.txt",
      "whitequark/return_block.txt",

      # Ripper cannot handle named capture groups in regular expressions.
      "regex.txt",

      # Ripper misreads literals spanning a heredoc and rejects valid %w and %i elements.
      "spanning_heredoc.txt",

      # Ripper interprets circular keyword arguments as method calls.
      "3.4/circular_parameters.txt",

      # Ripper doesn't emit `args_add_block` when endless method is prefixed by modifier.
      "4.0/endless_methods_command_call.txt",

      # https://bugs.ruby-lang.org/issues/21168#note-5
      "command_method_call_2.txt",
      "3.4/command_call_do_block_in_arguments.txt",
      "3.4-4.0/command_call_do_block_in_index_arguments.txt",
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
        # https://bugs.ruby-lang.org/issues/22310
        "pattern_alternation_non_captures.txt",
      ]
    end

    # Older Ripper versions read ?α as a character literal (Ruby #21186).
    incorrect << "ternary_operator_non_ascii.txt" unless Ripper.sexp_raw("a ?αvar1 : var2")

    # https://bugs.ruby-lang.org/issues/21669
    incorrect << "4.1/void_value.txt"
    # https://bugs.ruby-lang.org/issues/19107
    incorrect << "4.1/trailing_comma_after_method_arguments.txt"
    # https://bugs.ruby-lang.org/issues/22450
    incorrect << "jump_do_block_in_command_args.txt"

    # Skip these tests that we haven't implemented yet.
    omitted_sexp_raw = [
      "bom_leading_space.txt",
      "bom_spaces.txt",

      # Heredoc content boundaries and indentation differ in the translation.
      "dos_endings.txt",
      "heredocs_with_fake_newlines.txt",
      "seattlerb/heredoc__backslash_dos_format.txt",
      "seattlerb/heredoc_backslash_nl.txt",
      "seattlerb/heredoc_nested.txt",
      "seattlerb/heredoc_squiggly_blank_line_plus_interpolation.txt",
      "tilde_heredocs.txt",
      "unparser/corpus/semantic/dstr.txt",
      "whitequark/dedenting_heredoc.txt",
      "whitequark/parser_drops_truncated_parts_of_squiggly_heredoc.txt",
      "whitequark/parser_slash_slash_n_escaping_in_literals.txt",
      "whitequark/slash_newline_in_heredocs.txt",
    ]

    omitted_lex = [
      # Ripper's lex state on a newline delimited %r depends on what follows it.
      "heredoc_percent_newline_delimiter.txt",

      # Ripper skips registering keyword parameters as locals in f_label.
      "unparser/corpus/literal/def.txt",

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

    def test_leading_void_stmt
      [
        ";;x; y;",
        "(;x)",
        "(\nx;)",
        '"#{;x}"',
        "if x; y end",
        "if x;; y end",
        "foo { # ;\n x }",
        "class C < D; x end",
        "class C\n x; rescue; y; else\n z end"
      ].each { |source| assert_ripper_sexp_raw(source) }
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

    def test_command_and_pattern_productions
      [
        "m(A::B {})", "m 1 do end.f 2", "m 1 do end.f(2) do end",
        "loop { break m 1 do end.g }", "loop { break m(1) do end.g }",
        "def f; return super 1 do end; end", "def f; return super 1 do end.g; end",
        "def f; yield yield 1; end", "def f; super yield; end",
        "not(a and b) in true",
        "m(self.a = x)",
        "->(x: ->(x) { x }) { x }", "( #;\n x)"
      ].each do |source|
        assert_ripper_sexp_raw(source)
      end
    end

    def test_parentheses_in_nested_patterns
      [
        "x in ((y))", "x => [(1), *, (2)]", "x in [*, (1), *]", "x in {key: (1)}",
        "x in ((1) => y)", "x in ((1) | (2))", "x in ^((y))"
      ].each do |source|
        assert_ripper_sexp_raw(source)
      end
    end

    def test_parenthesized_patterns_with_guards
      [
        "case x; in (y) if z; end",
        "case x; in ((y)) unless (y); end",
        "case x; in (a) if (a) then a; in (b) unless (b) then b; end"
      ].each do |source|
        assert_ripper_sexp_raw(source)
      end
    end

    def test_not_with_empty_parentheses
      ["not()", "not ()", "not(())", "not(\n)", "not\n()"].each do |source|
        assert_ripper_sexp_raw(source)
      end
    end

    def test_command_as_an_index_write_argument
      ["matrix[m 1] = x", "matrix[m 1, &block] = x", "matrix[m(1)] = x", "matrix[m(1), 2] = x"].each do |source|
        assert_ripper_sexp_raw(source)
      end
    end

    def test_index_writes_without_a_trailing_comma
      ["matrix[1, 2] = x, y", "matrix[1 # ,\n] = x", "matrix[<<DOC\n,\nDOC\n] = x"].each do |source|
        assert_ripper_sexp_raw(source)
      end
    end

    def test_endless_method_argument_with_a_rescued_return
      assert_ripper_sexp_raw("outer(def f = not return rescue 2)")
      assert_ripper_sexp_raw("outer(def f = not return v rescue 2)") if RUBY_VERSION >= "4.0"
    end

    def test_block_call_events_after_a_jump
      %w[return break next].each do |keyword|
        ["m x do end.tail y", "obj.+ x do end.tail {}", "super x do end.tail(x)", "m(x) do end.tail"].each do |call|
          assert_ripper_sexp_raw("def f; loop { #{keyword} #{call} }; end")
        end
      end
      assert_ripper_sexp_raw("def f; receive case v; when A; return m 1 do end.g; end; end")
      [
        "case m 1 do end.g; when A; x; end",
        "case x; in A if m 1 do end.g; x; end",
        "class << m 1 do end.g; end",
        "def (m 1 do end.g).f; end"
      ].each do |argument|
        assert_ripper_sexp_raw("def f; return #{argument}; end")
      end
    end

    def test_dedenting_blank_lines_in_heredocs
      ["\n", " \n", "\r\n", "\t\n"].each do |blank_line|
        source = "<<~DOC\n  first\n#{blank_line}DOC\n"
        assert_equal Ripper.sexp(source), Translation::Ripper.sexp(source), source
        assert_ripper_sexp_raw(source)
      end
    end

    def test_for_with_a_single_splat_target
      ["for *x in ary; end", "for * in ary; end", "for *x[k] in ary; end", "for *obj&.attr[k] in ary; end"].each do |source|
        assert_equal Ripper.sexp(source), Translation::Ripper.sexp(source), source
        assert_ripper_sexp_raw(source)
      end
    end

    def test_colon_colon_in_assignment_targets
      ["for obj::x in ary; end", "for obj::x, y in ary; end", "begin; rescue => obj::x; end"].each do |source|
        assert_equal Ripper.sexp(source), Translation::Ripper.sexp(source), source
        assert_ripper_sexp_raw(source)
      end
    end

    def test_keyword_method_names_in_assignment_targets
      ["r.class ||= v", "r::if &&= v", "r&.return += v", "r.class, a = v", "r::class, a = v", "for r::if in xs; end"].each do |source|
        assert_equal Ripper.sexp(source), Translation::Ripper.sexp(source), source
        assert_ripper_sexp_raw(source)
      end
    end

    def test_command_brace_block_ownership
      sources = [
        "outer super (x) {}", "outer super(x) {}", "def f; outer yield (x) {}; end",
        "outer defined? (x) {}", "outer inner(x) {} do end"
      ]
      if RUBY_VERSION >= "4.0"
        sources.concat([
          "outer def f = super (x) {}", "outer def f = not super (x) {}",
          "outer def f = super (x) rescue y", "outer def f = obj.x = y"
        ])
      end
      sources << "f x do end.g (y) {}.h" if RUBY_VERSION >= "4.1"

      sources.each do |source|
        assert_equal Ripper.sexp(source), Translation::Ripper.sexp(source), source
        assert_ripper_sexp_raw(source)
      end
    end

    def test_keyword_parameter_registration
      # Ripper's treatment of the parameter name in its own default changed in Ruby 3.4.
      if RUBY_VERSION < "3.4"
        ["def f(x: x +1); end", "def f(x: x /2); end", "->x: x &() {}"].each { |source| assert_ripper_sexp_raw(source) }
      else
        assert_ripper_sexp_raw("x = 1; ->(x: x) { x }")
        assert_ripper_sexp_raw("x = 0; ->(x: x +1) {}")
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

    def test_encoding
      source = '"わたし"'.encode(Encoding::Windows_31J)
      assert_equal(Ripper.tokenize(source), Translation::Ripper.tokenize(source))
      assert_equal(Ripper.sexp(source), Translation::Ripper.sexp(source))
    end

    def test_encoding_method
      source = "foo"
      assert_equal(Ripper.new(source).tap(&:parse).encoding, Ruby::Prism::Translation::Ripper.new(source).tap(&:parse).encoding)

      source = "foo".b
      assert_equal(Ripper.new(source).tap(&:parse).encoding, Ruby::Prism::Translation::Ripper.new(source).tap(&:parse).encoding)

      source = "# encoding: euc-jp"
      assert_equal(Ripper.new(source).tap(&:parse).encoding, Ruby::Prism::Translation::Ripper.new(source).tap(&:parse).encoding)

      source = "# encoding: euc-jp".b
      assert_equal(Ripper.new(source).tap(&:parse).encoding, Ruby::Prism::Translation::Ripper.new(source).tap(&:parse).encoding)
    end

    def test_end_seen
      source = ""
      assert_equal(Ripper.new(source).tap(&:parse).end_seen?, Ruby::Prism::Translation::Ripper.new(source).tap(&:parse).end_seen?)

      source = "__END__"
      assert_equal(Ripper.new(source).tap(&:parse).end_seen?, Ruby::Prism::Translation::Ripper.new(source).tap(&:parse).end_seen?)
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
      assert_equal Ripper.sexp_raw(source), Ruby::Prism::Translation::Ripper.sexp_raw(source)
    end

    def assert_ripper_lex(source)
      prism = Translation::Ripper.lex(source)
      ripper = Ripper.lex(source)

      # Ruby::Prism emits tokens by their order in the code, not in parse order
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
