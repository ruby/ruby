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

    def test_bare_method_parameters_allow_trailing_comma_from_ruby_4_1
      ["def f x,; end", "def self.f *xs,; end"].each do |source|
        assert Ruby::Prism.parse_success?(source, version: "4.1"), source
        refute Ruby::Prism.parse_success?(source, version: "4.0"), source
      end

      refute Ruby::Prism.parse_success?("def f &block,; end", version: "4.1")
      refute Ruby::Prism.parse_success?("def f x,\nend", version: "4.1")
    end

    def test_end_block_exits_use_the_loop_inside_the_block
      ["break", "break 1", "next", "next 1", "redo"].each do |jump|
        %w[while until].each do |modifier|
          source = "END { #{jump} } #{modifier} ready"
          assert_equal [:invalid_block_exit], Ruby::Prism.parse(source, version: "4.1").errors.map(&:type), source
          assert Ruby::Prism.parse_success?(source, version: "4.0"), source
          assert Ruby::Prism.parse_success?("END { #{jump} #{modifier} ready }", version: "4.1"), jump
        end
      end
    end

    def test_end_block_retry_uses_the_rescue_inside_the_block
      ["x", "x = f arg", "* = value"].each do |body|
        source = "#{body} rescue END { retry }"
        assert_equal [:invalid_retry_without_rescue], Ruby::Prism.parse(source).errors.map(&:type), source
      end
      assert Ruby::Prism.parse_success?("END { x rescue retry }")
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

    def test_loop_modifier_owns_only_the_exits_in_its_statement
      %w[break next redo].each do |jump|
        ["while", "until"].each do |modifier|
          source = "def f = (#{jump}) #{modifier} x"
          assert_equal [:invalid_block_exit], Ruby::Prism.parse(source).errors.map(&:type), source
          assert Ruby::Prism.parse_success?("def f = (#{jump} #{modifier} x)")
          assert Ruby::Prism.parse_success?("class << (#{jump} if x); end #{modifier} y")
          assert Ruby::Prism.parse_success?("class C < (#{jump} if x); end #{modifier} y")
          refute Ruby::Prism.parse_success?("class << self; #{jump}; end #{modifier} y")
        end
      end
    end

    def test_singleton_class_return_uses_its_enclosing_method
      source = "-> { class << self; return; end }"
      assert Ruby::Prism.parse_success?(source, version: "3.3")
      assert_equal [:return_invalid], Ruby::Prism.parse(source, version: "3.4").errors.map(&:type)
      assert Ruby::Prism.parse_success?("def f; #{source}; end")
      refute Ruby::Prism.parse_success?("def f; class << self; class << self; return; end; end; end")
    end

    def test_class_header_starts_a_new_rescue_context
      ["class << (retry if x); end", "class C < (retry if x); end"].each do |header|
        assert_equal [:invalid_retry_without_rescue], Ruby::Prism.parse("x rescue #{header}").errors.map(&:type)
      end
      assert Ruby::Prism.parse_success?("class << (x rescue (retry if b)); end")
      source = "begin; rescue; class << f { retry }; end; end"
      assert_equal [:invalid_retry_without_rescue], Ruby::Prism.parse(source).errors.map(&:type)
    end

    def test_defined_validates_jumps_in_evaluated_receivers
      assert Ruby::Prism.parse_success?("defined?(f { retry })")
      assert_equal [:invalid_retry_without_rescue], Ruby::Prism.parse("defined?(f { retry }.g)").errors.map(&:type)
      assert_equal [:invalid_retry_without_rescue], Ruby::Prism.parse("defined?((defined?(f { retry }.g)).h)").errors.map(&:type)
      assert Ruby::Prism.parse_success?("x rescue defined?((retry if b).g)")
      %w[break next redo].each do |jump|
        source = "defined?((#{jump} if x).g)"
        assert_equal [:invalid_block_exit], Ruby::Prism.parse(source).errors.map(&:type), source
        assert Ruby::Prism.parse_success?("sink(#{source}) while y"), source
        refute Ruby::Prism.parse_success?("sink(defined?((def f = (#{jump})).g)) while y"), jump
      end
    end

    def test_retry_must_target_a_rescue_in_its_own_scope
      [
        "x rescue f { retry }",
        "x rescue -> { retry }",
        "x rescue (for i in xs; retry; end)",
        "if false; x rescue f { retry }; end"
      ].each do |source|
        result = Ruby::Prism.parse(source)
        assert_equal [:invalid_retry_without_rescue], result.errors.map(&:type), source
        assert_equal "retry", result.errors.first.location.slice
      end

      ["f { x rescue retry }", "x rescue (while b; retry; end)", "x rescue (for i in (retry if b); end)"].each do |source|
        assert Ruby::Prism.parse_success?(source), source
      end
    end

    def test_defined_yield_requires_a_method_when_the_receiver_is_evaluated
      [
        "defined?(!yield)",
        "defined?(not\nyield)",
        "defined?(not(yield))",
        "defined? ~yield",
        "defined? +yield",
        "defined? -yield",
        "defined?((!yield;))",
        "defined?(f(!yield))",
        "defined?(yield.foo)",
        "defined?(yield.(arg))",
        "defined?(f { yield }.g)",
        "defined?([*[!yield], 1])",
        "if false; defined?(!yield); end"
      ].each do |source|
        result = Ruby::Prism.parse(source)
        assert_equal [:invalid_yield], result.errors.map(&:type), source
        assert_equal "yield", result.errors.first.location.slice
      end

      [
        "defined?(yield)",
        "defined?(f(yield))",
        "defined?((yield)&.foo)",
        "defined?(x = !yield)",
        "defined?(/a/ =~ !yield)",
        "defined?([*xs, !yield])",
        "def f; defined?(!yield); end"
      ].each do |source|
        assert Ruby::Prism.parse_success?(source), source
      end
    end

    def test_defined_yield_tracks_versioned_operand_rules
      ["defined?({ k: !yield })", "defined?([*!yield])"].each do |source|
        assert Ruby::Prism.parse_success?(source, version: "3.3"), source
        refute Ruby::Prism.parse_success?(source, version: "3.4"), source
      end

      ["defined? (!yield;)", "defined?((if x; yield; end).foo)"].each do |source|
        refute Ruby::Prism.parse_success?(source, version: "3.4"), source
        assert Ruby::Prism.parse_success?(source, version: "4.0"), source
      end
    end

    def test_top_level_yield_is_invalid_in_dead_code
      assert_equal [:invalid_yield], Ruby::Prism.parse("yield if false").errors.map(&:type)
      assert Ruby::Prism.parse_success?("def f; yield if false; end")
    end

    def test_operators_after_yield
      ["yield", "yield()", "yield(x)"].each do |body|
        assert Ruby::Prism.parse_success?("def f; #{body} in Integer; end"), body
      end

      ["yield x", "yield (x)"].each do |body|
        result = Ruby::Prism.parse("def f; #{body} in Integer; end")
        assert_equal "in", result.errors.first.location.slice, body
        assert Ruby::Prism.parse_success?("def f; #{body} and ready; end"), body
      end

      result = Ruby::Prism.parse("def f; yield &blk in Integer; end")
      assert_equal [:unexpected_block_argument], result.errors.map(&:type)
    end

    def test_endless_method_rescue_rejects_unattached_do_block
      result = Ruby::Prism.parse("relay def f = 1 rescue 2 do end")

      assert_equal [:def_endless_do_block], result.errors.map(&:type)
      assert_equal "do end", result.errors.first.location.slice
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

    def test_block_parameter_defaults_require_a_primary
      ["defined? a", "defined? (a)", "..1", "def f = 1"].each do |value|
        ["x = ", "x: "].each do |parameter|
          result = Ruby::Prism.parse("m { |#{parameter}#{value}| x }")
          assert_include result.errors.map(&:type), :unexpected_parameter_default_value, value
        end
      end

      ["defined?(a)", "(defined? a)", "[..1]", "[def f = 1]", "-2", "(-2**2)"].each do |value|
        assert Ruby::Prism.parse_success?("m { |x = #{value}| x }"), value
      end

      ["x = ", "x: "].each do |parameter|
        result = Ruby::Prism.parse("m { |#{parameter}-2**2| x }")
        assert_equal [:unexpected_parameter_default_value], result.errors.map(&:type)
        assert_equal "**", result.errors.first.location.slice
      end
    end

    def test_singleton_method_receiver_with_array_splats
      ["[a, *xs]", "[*[a]]", "[a, *[]]", "[*[a], k: v]"].each do |receiver|
        assert Ruby::Prism.parse_success?("def (#{receiver}).f; end"), receiver
      end

      ["[a]", "[a, *[b]]", "[*[a], b]", "[a, *[b, *[c]]]"].each do |receiver|
        result = Ruby::Prism.parse("def (#{receiver}).f; end")
        assert_equal [:singleton_for_literals], result.errors.map(&:type), receiver
        assert_equal receiver, result.errors.first.location.slice
      end
    end

    def test_ruby_3_3_ellipsis_in_singleton_receivers
      ["1...2", "m { 1...2 }"].each do |receiver|
        source = "def (#{receiver}).f; end"
        assert_false Ruby::Prism.parse_success?(source, version: "3.3"), source
        assert Ruby::Prism.parse_success?(source, version: "3.4"), source
      end

      ["1..2", "...2", "m { |x| 1...2 }", "-> { 1...2 }"].each do |receiver|
        source = "def (#{receiver}).f; end"
        assert Ruby::Prism.parse_success?(source, version: "3.3"), source
      end

      source = "def (x...y).f; end"
      receiver = Ruby::Prism.parse(source, version: "3.3").value.statements.body.first.receiver.body
      assert_instance_of CallNode, receiver
      assert_instance_of RangeNode, receiver.arguments.arguments.first
      assert_instance_of RangeNode, Ruby::Prism.parse(source, version: "3.4").value.statements.body.first.receiver.body
    end

    def test_ruby_3_3_ellipsis_in_lambda_defaults
      assert_false Ruby::Prism.parse_success?("-> x = (...1) { x }", version: "3.3")
      assert Ruby::Prism.parse_success?("->(x = (...1)) { x }", version: "3.3")
      assert Ruby::Prism.parse_success?("-> x = ((...1)) { x }", version: "3.3")
      assert Ruby::Prism.parse_success?("-> x = (...1) { x }", version: "3.4")
    end

    def test_nested_void_statements
      ["if ((a => k); x); end", "case ((a => k); x) in 1 in 2; end"].each do |source|
        result = Ruby::Prism.parse(source, version: "4.1")
        assert_equal [:void_expression], result.errors.map(&:type), source
        assert_equal "a => k", result.errors.first.location.slice
      end

      assert Ruby::Prism.parse_success?("if ((a => k); x); end", version: "4.0")
    end

    def test_command_super_and_grouped_argument_blocks
      assert Ruby::Prism.parse_success?("super(1) {}")
      assert Ruby::Prism.parse_success?("m (1) {}")
      assert_equal [:argument_unexpected_block], Ruby::Prism.parse("super (1) {}").errors.map(&:type)

      ["super (x)", "defined? (x)", "defined? (x; y)", "def f = super (x)"].each do |argument|
        result = Ruby::Prism.parse("outer #{argument} {}", version: "4.1")
        assert_predicate result, :success?, argument
        assert_equal argument, result.statement.arguments.arguments.first.slice
        assert_equal "{}", result.statement.block.slice
      end
    end

    def test_do_after_a_command_ending_in_a_brace
      ["outer inner (x) {} do end", "outer super A::B {} do end"].each do |source|
        result = Ruby::Prism.parse(source)
        assert_predicate result, :failure?, source
        assert_equal "do", result.errors.first.location.slice
      end

      assert Ruby::Prism.parse_success?("outer inner(x) {} do end")
      assert Ruby::Prism.parse_success?("outer inner A::B {} do end")
    end

    def test_shorthand_after_a_command_block
      [".", "&.", "::"].each do |operator|
        source = "f x do end#{operator}()"
        assert Ruby::Prism.parse_success?("#{source}.g", version: "4.0"), source
        refute Ruby::Prism.parse_success?(source, version: "3.4"), source
        refute Ruby::Prism.parse_success?("#{source} do end"), source
        refute Ruby::Prism.parse_success?("#{source} {}"), source
        assert Ruby::Prism.parse_success?("(f x do end)#{operator}() {}"), source
      end

      source = "f x do end.g (y) {}.h"
      result = Ruby::Prism.parse(source, version: "4.1")
      assert_predicate result, :success?
      assert_equal :h, result.statement.name
      assert_equal "{}", result.statement.receiver.block.slice
      assert_equal "do end", result.statement.receiver.receiver.block.slice
      refute Ruby::Prism.parse_success?(source, version: "4.0")
    end

    def test_pattern_newlines_in_pins_and_guards
      ["x in ^(m k:\nand b)", "case x; in a if m k:\nand b; end"].each do |source|
        assert_false Ruby::Prism.parse_success?(source), source
        assert Ruby::Prism.parse_success?(source.tr("\n", " ")), source
      end
    end

    def test_range_patterns_require_literal_bounds
      ["..", "1.."].each do |range|
        result = Ruby::Prism.parse("case x; in #{range}-2**2; end")
        assert_equal [:pattern_expression_after_range], result.errors.map(&:type)
        assert_equal "-2**2", result.errors.first.location.slice
        assert Ruby::Prism.parse_success?("case x; in #{range}-2; end")
      end
    end

    def test_jumps_in_parameter_defaults_and_defined
      assert Ruby::Prism.parse_success?("defined?(def f = break)")
      assert Ruby::Prism.parse_success?("->(x = (break if b)) { x }")
      assert_false Ruby::Prism.parse_success?("m { def f = break }")
    end

    def test_jump_with_command_arguments_in_a_term
      result = Ruby::Prism.parse("def f; x && return m 1 do end.g; end")
      assert_equal [:expect_eol_after_statement], result.errors.map(&:type)
      assert_equal "m", result.errors.first.location.slice
    end

    def test_call_on_jump_with_an_invalid_block_argument
      result = Ruby::Prism.parse("def f(&); return super 1 do end, & .g; end")
      assert_equal [:invalid_comma, :unexpected_block_argument], result.errors.map(&:type)
      call = result.statement.body.body.first
      assert_equal :g, call.name
      assert_instance_of ReturnNode, call.receiver
    end

    def test_jumps_in_for_targets
      %w[break next redo].each do |jump|
        assert Ruby::Prism.parse_success?("for obj[(#{jump} if done)] in ary; end")
        assert_false Ruby::Prism.parse_success?("for obj in (#{jump} if done); end")
        assert Ruby::Prism.parse_success?("loop { for obj in (#{jump} if done); end }")
      end
    end

    def test_jumps_in_for_collections
      [
        "for * in ready and break; end",
        "for * in value = work rescue next; end",
        "for * in if ready; redo end; end",
        "for * in case item; in Integer; break end; end"
      ].each do |source|
        assert_equal [:invalid_block_exit], Ruby::Prism.parse(source).errors.map(&:type), source
      end
    end

    def test_methods_and_singleton_classes_isolate_block_exits
      ["loop { def self.f; next 1; end }", "until ready; def f = break; end", "-> { class << self; redo; end }"].each do |source|
        assert_equal [:invalid_block_exit], Ruby::Prism.parse(source).errors.map(&:type), source
      end
    end

    def test_assignments_after_block_call_or_index_write
      ["m 1 do end.f, y = z", "m 1 do end::C = z", "self[k] = x.. += y"].each do |source|
        assert_false Ruby::Prism.parse_success?(source), source
      end
    end

    def test_parenthesized_targets_reject_newline_before_assignment
      ["(first, second\n= [1, 2])", "((first, second), third\n= [1, 2, 3])"].each do |source|
        result = Ruby::Prism.parse(source)

        assert_equal [:write_target_unexpected], result.errors.map(&:type), source
      end
    end

    def test_parenthesized_multiple_assignment_targets
      result = Ruby::Prism.parse("x, (a, b), (obj).c = values")
      assert_predicate result, :success?
      _, nested, field = result.statement.lefts
      assert_instance_of MultiTargetNode, nested
      assert_equal [:a, :b], nested.lefts.map(&:name)
      assert_instance_of CallTargetNode, field
      assert_equal "(obj)", field.receiver.slice

      assert Ruby::Prism.parse_success?("for ((a, b), c) in values; end")
      assert Ruby::Prism.parse_success?("x, *(obj)[0] = values")
      assert Ruby::Prism.parse_success?("(; a, b = values).c, x = values")

      [
        "(;a, b) = values",
        "x, (a, b).c = values",
        "x, (f((a, b))).c = values",
        "x, *(a, b) = values",
        "for (;a, b) in values; end",
        "for x, (a, b)[0] in values; end"
      ].each do |source|
        assert_false Ruby::Prism.parse_success?(source), source
      end
    end

    def test_rescue_handler_requires_a_complete_multiple_assignment
      ["(work rescue *xs)", "(work rescue x, y)"].each do |source|
        assert_equal [:write_target_unexpected], Ruby::Prism.parse(source).errors.map(&:type), source
      end
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

    def test_receiver_command_in_expression_and_assignment
      result = Ruby::Prism.parse("if obj.fetch arg and ready; end")
      assert_predicate result, :success?
      predicate = result.statement.predicate
      assert_instance_of AndNode, predicate
      assert_equal "obj", predicate.left.receiver.slice
      assert_equal ["arg"], predicate.left.arguments.arguments.map(&:slice)

      result = Ruby::Prism.parse("x = obj.fetch(arg) and ready")
      assert_predicate result, :success?
      assert_instance_of AndNode, result.statement
      assert_instance_of LocalVariableWriteNode, result.statement.left

      assert_false Ruby::Prism.parse_success?("if x = obj.fetch arg; end")
      assert_false Ruby::Prism.parse_success?("x = obj.fetch arg and ready")
    end

    def test_command_endless_definition_as_a_sole_argument
      assert Ruby::Prism.parse_success?("f(def g = obj.fetch x)", version: "4.0")
      assert_false Ruby::Prism.parse_success?("f(def g = obj.fetch x)", version: "3.4")
      assert_false Ruby::Prism.parse_success?("f(a, def g = obj.fetch x)", version: "4.0")
    end

    def test_comma_after_nested_command_assignment
      source = "x = y = f 1 rescue 2, z"
      errors = Ruby::Prism.parse(source).errors
      assert_equal [:invalid_comma], errors.map(&:type)
      assert_equal ",", errors.first.location.slice

      assert Ruby::Prism.parse_success?("x = y = f(1) rescue 2, z")
      assert Ruby::Prism.parse_success?("x = (y = f 1 rescue 2), z")
    end

    def test_composition_after_nested_assignment
      result = Ruby::Prism.parse("x = y ||= f x, y and ready")
      assert_equal [:expect_eol_after_statement], result.errors.map(&:type)
      assert_equal "and", result.errors.first.location.slice

      assert Ruby::Prism.parse_success?("x = y ||= f(x, y) and ready")
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
    end

    def test_leading_logical_label_does_not_turn_following_keyword_into_symbol
      ["and", "or"].each do |keyword|
        result = Ruby::Prism.parse("show\n#{keyword}:then", version: "4.0")

        assert_predicate result, :failure?
        assert_equal "then", result.errors.first.location.slice
      end
    end

    def test_expr_operators_require_an_arg_for_a_pattern
      [
        "1 in 2 in true",
        "case not(1 in 2 in true); in true; end",
        "1 and foo 2 in true",
        "!foo 1 do end in true",
        "1 and flags &= compute 3",
        "def f = return 1 in true"
      ].each do |source|
        refute_valid_syntax(source)
        assert_predicate Ruby::Prism.parse(source), :failure?, source
      end
    end

    def test_statement_modifiers_end_after_a_command_predicate
      %w[if unless while until].each do |modifier|
        [["|2", "|"], [" in Integer", "in"], [" => result", "=>"]].each do |suffix, operator|
          source = "value #{modifier} lookup key:#{suffix}"
          error = Ruby::Prism.parse(source).errors.fetch(0)
          assert_equal :expect_eol_after_statement, error.type, source
          assert_equal operator, error.location.slice, source
        end

        assert Ruby::Prism.parse_success?("value #{modifier} lookup(key:) | 2")
        assert Ruby::Prism.parse_success?("value #{modifier} lookup(key:) in Integer")
      end
    end

    def test_forwarding_after_a_rest_parameter
      source = "def f(opt = 1, *rest, ...) = rest"
      assert_equal [:parameter_forwarding_after_rest], Ruby::Prism.parse(source).errors.map(&:type)
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
