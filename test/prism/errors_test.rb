# frozen_string_literal: true

return if RUBY_VERSION < "3.3.0"

require_relative "test_helper"

module Ruby::Prism
  class ErrorsTest < TestCase
    base = File.expand_path("errors", __dir__)
    filepaths = Dir[ENV.fetch("FOCUS", "**/*.txt"), base: base]

    PARSE_Y_EXCLUDES = [
      # https://bugs.ruby-lang.org/issues/20409
      "#{base}/4.1/end_block_exit.txt"
    ]

    filepaths.each do |filepath|
      ruby_versions_for(filepath).each do |version|
        define_method(:"test_#{version}_#{File.basename(filepath, ".txt")}") do
          assert_errors(File.join(base, filepath), version)
        end
      end
    end

    def test_unterminated_quoted_symbol_closing_location
      {
        ':"#s' => :symbol_term_interpolated,
        ':"#{x}' => :symbol_term_interpolated,
        ":'s" => :symbol_term_dynamic
      }.each do |source, diagnostic|
        result = Ruby::Prism.parse(source)
        symbol = result.value.statements.body.first

        assert_equal [diagnostic], result.errors.map(&:type)
        assert_equal source, symbol.location.slice
        assert_nil symbol.closing_loc
      end
    end

    def test_quoted_labels_in_patterns
      ['o=>1,"":', 'o in [1, "key":]', 'o in 1 | "key":'].each do |source|
        assert_equal [:unexpected_label], Ruby::Prism.parse(source).errors.map(&:type), source
      end

      ['o => "key": 1', 'o => [1, {"": 2}]', 'o => 1, :""'].each do |source|
        assert Ruby::Prism.parse_success?(source), source
      end
    end

    def test_unclosed_array_location_covers_last_element
      source = '[r="#{ '
      result = Ruby::Prism.parse(source)
      array = result.value.statements.body.first

      assert_includes result.errors.map(&:type), :array_term
      assert_nil array.closing_loc
      assert_equal source, array.location.slice
      assert_equal array.elements.last.location.end_offset, array.location.end_offset
    end

    def test_implicit_method_rescue_rejects_constant_target
      ["", "StandardError "].each do |exceptions|
        result = Ruby::Prism.parse("def f; raise; rescue #{exceptions}=> CaughtError; end")

        assert_equal [:write_target_in_method], result.errors.map(&:type)
        assert_equal "CaughtError", result.errors.first.location.slice
      end
    end

    def test_anonymous_splat_at_the_end_of_command_arguments
      ["g *", "g 1, *", "super *", "return *"].each do |body|
        source = "def f(*) = #{body}"
        assert Ruby::Prism.parse_success?(source), source
        refute Ruby::Prism.parse_success?("def f = #{body}"), body
      end
      ["g 1, * rescue x", "g 1, * do end", "g 1, * and x", "g 1, * or x"].each do |body|
        assert Ruby::Prism.parse_success?("def f(*); #{body}; end"), body
        refute Ruby::Prism.parse_success?("def f(*) = #{body}"), body
      end
      ["g 1, *", "return *", "outer { g 1, * }", "outer { |*rest| g 1, * }"].each do |body|
        assert Ruby::Prism.parse_success?("def f(*)\n#{body}\nend"), body
        refute Ruby::Prism.parse_success?("def f\n#{body}\nend"), body
      end

      method = Ruby::Prism.parse("def f(*) = g 1, *").value.statements.body.first
      splat = method.body.body.first.arguments.arguments.last
      assert_instance_of Ruby::Prism::SplatNode, splat
      assert_nil splat.expression
    end

    def test_trailing_star_with_whitespace_requires_an_operand
      [" ", "\n"].each do |whitespace|
        result = Ruby::Prism.parse("def f(*) = g *#{whitespace}")
        assert_equal :expect_expression_after_operator, result.errors.first.type
      end
    end

    def test_retry_in_dead_code_still_requires_a_rescue_in_its_own_scope
      errors = Ruby::Prism.parse("if false; x rescue f { retry }; end").errors
      assert_equal [:invalid_retry_without_rescue], errors.map(&:type)
      assert_equal "retry", errors.first.location.slice
    end

    def test_end_block_exit_after_nested_defined_expressions
      nested = "defined?(" * 32 + "nil" + ")" * 32
      source = "defined?(begin; #{nested}; END { break }; end)\nEND { break }"

      errors = Ruby::Prism.parse(source, version: "4.1").errors
      assert_equal [:invalid_block_exit], errors.map(&:type)
      assert_equal 2, errors.first.location.start_line
    end

    def test_top_level_yield_is_invalid_in_dead_code
      assert_equal [:invalid_yield], Ruby::Prism.parse("yield if false").errors.map(&:type)
      assert Ruby::Prism.parse_success?("def f; yield if false; end")
    end

    def test_endless_method_rescue_rejects_unattached_do_block
      result = Ruby::Prism.parse("relay def f = 1 rescue 2 do end")

      assert_equal [:def_endless_do_block], result.errors.map(&:type)
      assert_equal "do end", result.errors.first.location.slice
    end

    def test_do_after_a_brace_command_in_an_endless_method_argument
      ["super A::B {}", "inner g (x) {}", "yield g (x) {}", "not super A::B {}", "return inner A::B {}"].each do |body|
        source = "outer def f = #{body} do end; tail"
        result = Ruby::Prism.parse(source, version: "4.0")
        assert_equal [:def_endless_do_block], result.errors.map(&:type), source
        assert_equal "do end", result.errors.first.location.slice
        outer, tail = result.value.statements.body
        assert_nil outer.block
        assert_equal :tail, tail.name
      end
    end

    def test_missing_rescue_handler_inside_bare_not_in_an_endless_def
      result = Ruby::Prism.parse("def f = not work rescue; tail")
      assert_equal [:rescue_modifier_value], result.errors.map(&:type)
      assert_equal "rescue", result.errors.first.location.slice
      definition, tail = result.value.statements.body
      rescue_node = definition.body.body.first.receiver
      assert_instance_of RescueModifierNode, rescue_node
      assert_instance_of ErrorRecoveryNode, rescue_node.rescue_expression
      assert_equal "tail", tail.slice
    end

    def test_module_name_rejects_symbol_ending_in_constant_token
      result = Ruby::Prism.parse("module:A; end")

      assert_equal [:module_name], result.errors.map(&:type)
      assert_equal ":A", result.errors.first.location.slice
    end

    def test_begin_with_rescue_and_ensure_rejects_void_values
      result = Ruby::Prism.parse("def f; x = begin; return :body; rescue; return :rescue; ensure; end; end")
      assert_equal [:void_expression], result.errors.map(&:type)
      assert_equal "return :body", result.errors.first.location.slice

      result = Ruby::Prism.parse("def f; x = begin; return :body; rescue; 1; ensure; return :ensure; end; end")
      assert_equal [:void_expression], result.errors.map(&:type)
      assert_equal "return :ensure", result.errors.first.location.slice
    end

    def test_bare_defined_in_a_block_default_preserves_the_next_parameter
      ["x = defined? a && b, y", "x: defined? (a), y:"].each do |parameters|
        result = Ruby::Prism.parse("m { |#{parameters}| x }")
        assert_equal [:unexpected_parameter_default_value], result.errors.map(&:type)
        assert_equal "defined?", result.errors.first.location.slice
        assert_equal :y, result.statement.block.parameters.parameters.compact_child_nodes.last.name
      end
    end

    def test_command_super_and_grouped_argument_blocks
      result = Ruby::Prism.parse("outer super(x) {}")
      assert_predicate result, :success?
      assert_nil result.statement.block
      assert_equal "{}", result.statement.arguments.arguments.first.block.slice
      assert Ruby::Prism.parse_success?("super(1) {}")
      assert Ruby::Prism.parse_success?("m (1) {}")
      assert_equal [:argument_unexpected_block], Ruby::Prism.parse("super (1) {}").errors.map(&:type)

      ["super (x)", "super (x; y)", "defined? (x)", "defined? (x; y)", "def f = super (x)"].each do |argument|
        result = Ruby::Prism.parse("outer #{argument} {}", version: "4.1")
        assert_predicate result, :success?, argument
        assert_equal argument, result.statement.arguments.arguments.first.slice
        assert_equal "{}", result.statement.block.slice
      end
    end

    def test_unexpected_super_block_in_delimited_arguments
      result = Ruby::Prism.parse("f(super (x) {}, y); tail")
      assert_equal [:argument_unexpected_block], result.errors.map(&:type)
      assert_equal "{}", result.errors.first.location.slice
      call, tail = result.value.statements.body
      assert_equal ["super (x) {}", "y"], call.arguments.arguments.map(&:slice)
      assert_equal :tail, tail.name
    end

    def test_command_brace_block_chained_after_a_command_block
      [".", "&.", "::"].each do |operator|
        source = "f x do end#{operator}g (y) {}.h"
        result = Ruby::Prism.parse(source, version: "4.1")
        assert_predicate result, :success?, source
        assert_equal :h, result.statement.name
        assert_equal "{}", result.statement.receiver.block.slice
        assert_equal "do end", result.statement.receiver.receiver.block.slice

        %w[3.3 3.4 4.0].each do |version|
          result = Ruby::Prism.parse(source, version: version)
          assert_equal [:argument_unexpected_block], result.errors.map(&:type), source
          assert_equal "{}", result.errors.first.location.slice
        end

        assert Ruby::Prism.parse_success?("f x do end#{operator}g(y) {}.h", version: "4.0")
        assert Ruby::Prism.parse_success?("(f x do end)#{operator}g (y) {}", version: "4.0")
      end
    end

    def test_pattern_newlines_in_pins_and_guards
      [
        "x in ^(m k:\nand b)",
        "x => [^(m k:\nand b)]",
        "case x; in a if m k:\nand b; end",
        "case x; in {} unless m k:\nand b; end",
        "case x; in a if m \"key\":\n::C; end"
      ].each do |source|
        assert_false Ruby::Prism.parse_success?(source), source
        assert Ruby::Prism.parse_success?(source.tr("\n", " ")), source
      end
    end

    def test_range_patterns_require_literal_bounds
      %w[.. ... 1.. 1...].each do |range|
        result = Ruby::Prism.parse("case x; in #{range}-2**2; end")
        assert_equal [:expect_in_delimiter, :unexpected_token_ignore], result.errors.map(&:type)
        assert_equal "**", result.errors.last.location.slice

        right = result.statement.conditions.first.pattern.right
        assert_instance_of IntegerNode, right
        assert_equal(-2, right.value)
      end
    end

    def test_call_on_jump_with_an_invalid_block_argument
      result = Ruby::Prism.parse("def f(&); return super 1 do end, & .g; end")
      assert_equal [:invalid_comma, :unexpected_block_argument], result.errors.map(&:type)
      call = result.statement.body.body.first
      assert_equal :g, call.name
      assert_instance_of ReturnNode, call.receiver
    end

    def test_jump_with_a_chained_command_block_in_call_arguments
      %w[return break next].each do |keyword|
        argument = "#{keyword} r z do end.t"
        result = Ruby::Prism.parse("loop { o(#{argument}) }")
        assert_equal [:void_expression], result.errors.map(&:type), keyword
        assert_equal argument, result.errors.first.location.slice

        jump = result.statement.block.body.body.first.arguments.arguments.first
        assert_equal keyword, jump.keyword
        assert_equal :t, jump.arguments.arguments.first.name

        grouped = Ruby::Prism.parse("loop { o((#{argument})) }")
        assert_empty grouped.errors
        call = grouped.statement.block.body.body.first.arguments.arguments.first.body.body.first
        assert_equal :t, call.name
        assert_equal keyword, call.receiver.keyword
      end
    end

    def test_parenthesized_targets_reject_newline_before_assignment
      ["(first, second\n= [1, 2])", "((first, second), third\n= [1, 2, 3])"].each do |source|
        result = Ruby::Prism.parse(source)

        assert_equal [:write_target_unexpected], result.errors.map(&:type), source
      end
    end

    def test_unexpected_in_after_an_assignment_inside_a_case_clause
      source = "case x; in First; (work rescue u, v = values in Second); tail; in Third; end"
      result = Ruby::Prism.parse(source)
      assert_equal [:expect_eol_after_statement], result.errors.map(&:type)
      assert_equal source.index("in Second"), result.errors.first.location.start_offset
      assert_equal ["First", "Third"], result.statement.conditions.map { |clause| clause.pattern.slice }
      assert_equal "tail", result.statement.conditions.first.statements.body.last.slice
    end

    def test_missing_delimiter_between_in_clauses_after_a_rescue_handler
      source = "case x; in First; work rescue u, v = values in Second in Third; end"
      result = Ruby::Prism.parse(source)
      assert_equal [:expect_in_delimiter], result.errors.map(&:type)
      assert_equal source.index(" in Third"), result.errors.first.location.start_offset
      assert_equal ["First", "Second", "Third"], result.statement.conditions.map { |clause| clause.pattern.slice }
    end

    def test_then_after_a_pattern_match_in_a_case_body
      source = "case v; in A; lhs + rhs in B then tail; in C; end"
      result = Ruby::Prism.parse(source)
      assert_equal :expect_eol_after_statement, result.errors.fetch(0).type
      assert_equal "then", result.errors.first.location.slice
      assert_equal ["A", "C"], result.statement.conditions.map { |clause| clause.pattern.slice }
      assert_instance_of MatchPredicateNode, result.statement.conditions.first.statements.body.first
      assert_equal "tail", result.statement.conditions.first.statements.body.last.slice
    end

    def test_target_list_after_a_statement_in_parentheses
      result = Ruby::Prism.parse("(work; a, b)")
      assert_equal [:write_target_unexpected], result.errors.map(&:type)
      write = result.statement.body.body.last
      assert_instance_of MultiWriteNode, write
      assert_equal [:a, :b], write.lefts.map(&:name)
      assert_instance_of ErrorRecoveryNode, write.value

      assert Ruby::Prism.parse_success?("(work; a, b = values)")
      assert Ruby::Prism.parse_success?("((a, b\n), c) = values")
    end

    def test_class_headers_respect_enclosing_loop_condition
      ["while", "until"].each do |keyword|
        result = Ruby::Prism.parse("#{keyword} class << target do end; end; end")

        assert_includes result.errors.map(&:type), :expect_singleton_class_delimiter
      end

      result = Ruby::Prism.parse("while class A < target do end; end; end")
      assert_includes result.errors.map(&:type), :class_unexpected_end
    end

    def test_singleton_method_definition_rejects_setter_name_as_receiver
      [".", "::"].each do |operator|
        result = Ruby::Prism.parse("def target=#{operator}greet; end")

        assert_equal [:def_receiver_setter], result.errors.map(&:type)
        assert_equal "target=", result.errors.first.location.slice
      end
    end

    def test_shorthand_hash_labels_resolve_block_parameters
      assert_equal [:it_not_allowed_ordinary], Ruby::Prism.parse("proc { |x| {it:} }", version: "3.4").errors.map(&:type)
      assert_equal [:it_not_allowed_numbered], Ruby::Prism.parse("proc { _1; {it:} }", version: "3.4").errors.map(&:type)
      assert_equal [:numbered_parameter_it], Ruby::Prism.parse("proc { it; {_2:} }", version: "3.4").errors.map(&:type)

      numbered = Ruby::Prism.parse_statement("proc { {_2:} }").block.parameters
      assert_instance_of NumberedParametersNode, numbered
      assert_equal 2, numbered.maximum

      assert_nil Ruby::Prism.parse_statement("proc { {it:} }", version: "3.3.0").block.parameters
      assert_nil Ruby::Prism.parse("it = 1; proc { {it:} }", version: "3.4").value.statements.body.last.block.parameters
    end

    def test_uppercase_shorthand_hash_labels_reject_method_suffixes
      ["Flag?", "Status!"].each do |name|
        result = Ruby::Prism.parse("{ #{name}: }")

        assert_equal [:invalid_constant_read], result.errors.map(&:type)
        assert_equal name, result.errors.first.location.slice
      end

      assert_equal [:invalid_local_variable_read], Ruby::Prism.parse("{ flag?: }").errors.map(&:type)
    end

    def test_colon_delimited_percent_symbol_requires_hash_rocket
      result = Ruby::Prism.parse("{ %s:: 1 }")
      assert_equal [:hash_rocket], result.errors.map(&:type)
    end

    def test_beginless_range_rejects_unparenthesized_binary_range_operand
      assert_equal [:unexpected_range_operator], Ruby::Prism.parse("p(...1..2)").errors.map(&:type)
      errors = Ruby::Prism.parse("f(...x.. && y)").errors
      assert_equal [:unexpected_range_operator], errors.map(&:type)
      assert_equal "..", errors.first.location.slice
    end

    def test_leading_logical_label_does_not_turn_following_keyword_into_symbol
      ["and", "or"].each do |keyword|
        result = Ruby::Prism.parse("show\n#{keyword}:then", version: "4.0")

        assert_predicate result, :failure?
        assert_equal "then", result.errors.first.location.slice
      end
    end

    def test_case_required_match_predicate_is_void
      result = Ruby::Prism.parse("case value => captured in Integer; :body; end")
      assert_equal [:void_expression], result.errors.map(&:type)
      assert_equal "value => captured", result.errors.first.location.slice
      assert_equal "Integer", result.statement.conditions.first.pattern.slice
    end

    def test_keyword_not_is_not_a_write_target
      [
        "not() = :value",
        "*not() = value",
        "first, not() = 1, 2",
        "begin; rescue => not(); end",
        "for not() in []; end",
        "not() |= 42",
        "not() &&= 1",
        "not() ||= 1",
        "not flag.. ||= 1"
      ].each do |source|
        assert_equal [:write_target_unexpected], Ruby::Prism.parse(source).errors.map(&:type), source
      end

      result = Ruby::Prism.parse("first, not() = 1, 2")
      target = result.statement.lefts.last
      assert_kind_of ErrorRecoveryNode, target
      assert_equal "not()", target.unexpected.location.slice
    end

    def test_mixed_encoding_locations
      ["ASCII-8BIT", "US-ASCII", "EUC-JP"].each do |encoding|
        next if ENV["PRISM_BUILD_MINIMAL"] && encoding == "EUC-JP"

        bytes = encoding == "EUC-JP" ? "\xA1\xA1" : "\xA1"
        source = "\"\\u{df}abc#{bytes}\"".b
        error = Ruby::Prism.parse(source, encoding: encoding).errors.find { |diagnostic| diagnostic.type == :mixed_encoding }

        assert_not_nil error
        assert_equal "UTF-8 mixed within #{encoding} source", error.message
        assert_equal 10, error.location.start_offset
        assert_equal bytes.bytesize, error.location.length
        assert_equal bytes.b, error.location.slice.b
      end
    end

    def test_mixed_encoding_location_for_invalid_multibyte_character
      return if ENV["PRISM_BUILD_MINIMAL"]

      source = "\"\\u{df\xD3&".b
      error = Ruby::Prism.parse(source, encoding: "EUC-JP").errors.find { |diagnostic| diagnostic.type == :mixed_encoding }

      assert_not_nil error
      assert_equal 6, error.location.start_offset
      assert_equal 1, error.location.length
      assert_equal "\xD3".b, error.location.slice.b
    end

    def test_extra_unicode_codepoint_locations
      ["a", "00", "a b", "a "].each do |extra|
        result = Ruby::Prism.parse("?\\u{0 #{extra}}")
        error = result.errors.find { |diagnostic| diagnostic.type == :escape_invalid_unicode_literal }

        assert_not_nil error
        assert_equal 6, error.location.start_offset
        assert_equal extra, error.location.slice
      end
    end

    def test_newline_preceding_eof
      err = Ruby::Prism.parse("foo(").errors.first
      assert_equal 1, err.location.start_line

      err = Ruby::Prism.parse("foo(\n").errors.first
      assert_equal 1, err.location.start_line

      err = Ruby::Prism.parse("foo(\n\n\n\n\n").errors.first
      assert_equal 5, err.location.start_line
    end

    def test_embdoc_beginning_control_characters
      ["\0", "\C-d", "\C-z"].each do |character|
        ["\n", "\r\n"].each do |newline|
          comment = "=begin#{character}#{newline}ignored#{newline}=end#{newline}"
          result = Ruby::Prism.parse("#{comment}1#{newline}")

          assert_predicate result, :success?
          assert_equal 1, result.statement.value
          assert_equal 1, result.comments.length
          assert_kind_of EmbDocComment, result.comments.first
          assert_equal comment, result.comments.first.location.slice
        end
      end
    end

    def test_unterminated_embdoc_after_control_character
      ["\C-d", "\C-z"].each do |character|
        result = Ruby::Prism.parse("=begin#{character}")
        assert_equal [:embdoc_term], result.errors.map(&:type)
      end
    end

    def test_embdoc_ending
      source = <<~RUBY
        =begin\n=end
        =begin\n=end\0
        =begin\n=end\C-d
        =begin\n=end\C-z
      RUBY

      source.each_line do |line|
        assert_valid_syntax(source)
        assert_predicate Ruby::Prism.parse(source), :success?
      end
    end

    def test_unterminated_string_closing
      statement = Ruby::Prism.parse_statement("'hello")
      assert_equal statement.unescaped, "hello"
      assert_nil statement.closing
    end

    def test_unterminated_interpolated_string_closing
      statement = Ruby::Prism.parse_statement('"hello')
      assert_equal statement.unescaped, "hello"
      assert_nil statement.closing
    end

    def test_unterminated_empty_string_closing
      statement = Ruby::Prism.parse_statement('"')
      assert_empty statement.unescaped
      assert_nil statement.closing
    end

    def test_unterminated_string_with_an_invalid_unicode_escape
      result = Ruby::Prism.parse('"\u{xxxx')
      statement = result.value.statements.body.first
      assert_kind_of StringNode, statement
      assert_equal '\u{xxxx', statement.content
      assert_nil statement.closing

      assert_equal [:escape_invalid_unicode, :escape_invalid_unicode_term, :string_interpolated_term], result.errors.map(&:type)
      assert_equal [4, 4, 0], result.errors.map { |error| error.location.start_offset }
    end

    def test_missing_unary_receiver_reports_following_token
      { "+" => "end-of-input", "+ )" => "')'" }.each do |source, name|
        error = Ruby::Prism.parse(source).errors.first
        assert_equal :unary_receiver, error.type
        assert_equal "unexpected #{name}, expected a receiver for unary `+`", error.message
        assert_equal "+", error.location.slice
      end
    end

    def test_recovery_names_the_enclosing_clause
      {
        "begin; rescue; 1 + end" => "'rescue' clause",
        "def f; ensure; 1 + end" => "'ensure' clause",
        "if x; else; 1 + end" => "'else' clause"
      }.each do |source, name|
        error = Ruby::Prism.parse(source).errors.find { |diagnostic| diagnostic.type == :unexpected_token_close_context }
        assert_not_nil error, source
        assert_equal "unexpected 'end', assuming it is closing the parent #{name}", error.message
        assert_equal "end", error.location.slice
      end
    end

    def test_unexpected_backslash
      {
        "\\ " => "escaped space",
        "\\\f" => "escaped form feed",
        "\\\t" => "escaped horizontal tab",
        "\\\v" => "escaped vertical tab",
        "\\\r" => "escaped carriage return",
        "\\" => "backslash"
      }.each do |escape, description|
        result = Ruby::Prism.parse("#{escape}1")
        assert_equal [:unexpected_token_ignore], result.errors.map(&:type)
        assert_equal "unexpected #{description}, ignoring it", result.errors.first.message
        assert_equal escape, result.errors.first.location.slice
        assert_equal 1, result.value.statements.body.first.value
      end

      assert_empty Ruby::Prism.parse("\\\n1").errors
      assert_empty Ruby::Prism.parse("\\\r\n1").errors
    end

    def test_regexp_encoding_option_mismatch_error
      # UTF-8 char with ASCII-8BIT modifier
      result = Ruby::Prism.parse('/Ȃ/n')
      assert_includes result.errors.map(&:type), :regexp_encoding_option_mismatch

      # UTF-8 char with EUC-JP modifier
      result = Ruby::Prism.parse('/Ȃ/e')
      assert_includes result.errors.map(&:type), :regexp_encoding_option_mismatch

      # UTF-8 char with Windows-31J modifier
      result = Ruby::Prism.parse('/Ȃ/s')
      assert_includes result.errors.map(&:type), :regexp_encoding_option_mismatch

      # UTF-8 char with UTF-8 modifier
      result = Ruby::Prism.parse('/Ȃ/u')
      assert_empty result.errors
    end

    def test_long_formatted_messages
      [1, 255, 256, 4096].each do |length|
        identifier = "E" * length
        messages = Ruby::Prism.parse("<<#{identifier}\n").errors.map(&:message)
        assert_includes messages, "unterminated heredoc; can't find string \"#{identifier}\" anywhere before EOF"
      end
    end

    def test_heredoc_diagnostic_with_embedded_nul
      result = Ruby::Prism.parse("<<\"BEFORE\0AFTER\"\n")
      assert_equal ["unterminated heredoc; can't find string \"BEFORE\" anywhere before EOF"], result.errors.map(&:message)
    end

    def test_unterminated_quoted_heredoc_identifier_at_eof
      ["'", '"', "`"].each do |quote|
        ["<<", "<<-", "<<~"].each do |opener|
          source = "alias#{opener}#{quote}"
          error = Ruby::Prism.parse(source).errors.find { |diagnostic| diagnostic.type == :heredoc_identifier }
          assert_not_nil error, source
          assert_equal source.bytesize, error.location.start_offset
          assert_equal 0, error.location.length
        end
      end
    end

    def test_unexpected_statement_as_argument
      result = Ruby::Prism.parse("f(alias a b, 1); tail")
      assert_equal [:statement_alias], result.errors.map(&:type)

      call, tail = result.value.statements.body
      unexpected, integer = call.arguments.arguments
      assert_instance_of ErrorRecoveryNode, unexpected
      assert_instance_of AliasMethodNode, unexpected.unexpected
      assert_equal 1, integer.value
      assert_equal :tail, tail.name
    end

    def test_unexpected_undef_preserves_its_names
      result = Ruby::Prism.parse("f(undef a, b)")
      assert_equal [:statement_undef], result.errors.map(&:type)

      argument = result.statement.arguments.arguments.fetch(0)
      assert_instance_of ErrorRecoveryNode, argument
      assert_instance_of UndefNode, argument.unexpected
      assert_equal %w[a b], argument.unexpected.names.map(&:slice)
    end

    def test_unexpected_statement_as_array_element
      result = Ruby::Prism.parse("[END {}, 1]; tail")
      assert_equal [:statement_postexe_end], result.errors.map(&:type)

      array, tail = result.value.statements.body
      unexpected, integer = array.elements
      assert_instance_of ErrorRecoveryNode, unexpected
      assert_instance_of PostExecutionNode, unexpected.unexpected
      assert_equal 1, integer.value
      assert_equal :tail, tail.name
    end

    def test_begin_in_a_statement_list_and_in_a_rescue_modifier
      assert Ruby::Prism.parse_success?("BEGIN { BEGIN { work } }")

      nested = Ruby::Prism.parse("begin; BEGIN { work }; end")
      assert_equal [:begin_upcase_toplevel], nested.errors.map(&:type)
      assert_instance_of PreExecutionNode, nested.statement.statements.body.first

      result = Ruby::Prism.parse("work rescue BEGIN { cleanup }; tail")
      assert_equal [:begin_upcase_toplevel], result.errors.map(&:type)
      rescue_modifier, tail = result.value.statements.body
      assert_instance_of ErrorRecoveryNode, rescue_modifier.rescue_expression
      assert_instance_of PreExecutionNode, rescue_modifier.rescue_expression.unexpected
      assert_equal :tail, tail.name
    end

    def test_unexpected_statement_preserves_the_following_list_element
      assignment = Ruby::Prism.parse("x = 1, END {}, y")
      assert_equal [:statement_postexe_end], assignment.errors.map(&:type)
      _, unexpected, sibling = assignment.statement.value.elements
      assert_instance_of PostExecutionNode, unexpected.unexpected
      assert_equal :y, sibling.name

      ["END {}", "*END {}"].each do |condition|
        result = Ruby::Prism.parse("case x; when #{condition}, y; end")
        assert_equal [:statement_postexe_end], result.errors.map(&:type)
        first, sibling = result.statement.conditions.first.conditions
        first = first.expression if first.is_a?(SplatNode)
        assert_instance_of PostExecutionNode, first.unexpected
        assert_equal :y, sibling.name
      end
    end

    def test_void_jump_receiver_preserves_the_enclosing_expression
      result = Ruby::Prism.parse("x = return A::B {}.f or ready")
      assert_equal [:void_expression], result.errors.map(&:type)
      assert_instance_of OrNode, result.statement
      assert_instance_of ReturnNode, result.statement.left.value.receiver
      assert_equal :ready, result.statement.right.name
    end

    def test_incomplete_def_closing_loc
      statement = Ruby::Prism.parse_statement("def f; 123")
      assert_nil(statement.end_keyword)
    end

    def test_unclosed_interpolation
      statement = Ruby::Prism.parse_statement("\"\#{")
      assert_equal('"', statement.opening)
      assert_nil(statement.closing)

      assert_equal(1, statement.parts.count)
      assert_equal('#{', statement.parts[0].opening)
      assert_equal("", statement.parts[0].closing)
      assert_nil(statement.parts[0].statements)
    end

    def test_unclosed_heredoc_and_interpolation
      statement = Ruby::Prism.parse_statement("<<D\n\#{")
      assert_equal("<<D", statement.opening)
      assert_nil(statement.closing)

      assert_equal(1, statement.parts.count)
      assert_equal('#{', statement.parts[0].opening)
      assert_equal("", statement.parts[0].closing)
      assert_nil(statement.parts[0].statements)
    end

    private

    def assert_errors(filepath, version)
      expected = File.read(filepath, binmode: true, external_encoding: Encoding::UTF_8)

      source = expected.lines.grep_v(/^\s*\^/).join.gsub(/\n*\z/, "")
      if CURRENT_MAJOR_MINOR == version && !PARSE_Y_EXCLUDES.include?(filepath)
        refute_valid_syntax(source)
      end

      result = Ruby::Prism.parse(source, version: version)
      errors = result.errors
      refute_empty errors, "Expected errors in #{filepath}"

      actual = result.errors_format
      if expected != actual && ENV["UPDATE_SNAPSHOTS"]
        File.write(filepath, actual)
      end

      assert_equal expected, actual, "Expected errors to match for #{filepath}"
    end
  end
end
