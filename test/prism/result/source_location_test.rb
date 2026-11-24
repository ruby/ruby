# frozen_string_literal: true

require_relative "../test_helper"

module Ruby::Prism
  class SourceLocationTest < TestCase
    def test_AliasGlobalVariableNode
      assert_location(AliasGlobalVariableNode, "alias $foo $bar")
    end

    def test_AliasMethodNode
      assert_location(AliasMethodNode, "alias foo bar")
    end

    def test_AlternationPatternNode
      assert_location(AlternationPatternNode, "foo => 0 | 1", 7...12, &:pattern)
    end

    def test_AndNode
      assert_location(AndNode, "foo and bar")
      assert_location(AndNode, "foo && bar")
    end

    def test_ArgumentsNode
      assert_location(ArgumentsNode, "foo(bar, baz, qux)", 4...17, &:arguments)
    end

    def test_ArrayNode
      assert_location(ArrayNode, "[foo, bar, baz]")
      assert_location(ArrayNode, "%i[foo bar baz]")
      assert_location(ArrayNode, "%I[foo bar baz]")
      assert_location(ArrayNode, "%w[foo bar baz]")
      assert_location(ArrayNode, "%W[foo bar baz]")
    end

    def test_ArrayPatternNode
      assert_location(ArrayPatternNode, "foo => bar, baz", 7...15, &:pattern)
      assert_location(ArrayPatternNode, "foo => [bar, baz]", 7...17, &:pattern)
      assert_location(ArrayPatternNode, "foo => *bar", 7...11, &:pattern)
      assert_location(ArrayPatternNode, "foo => []", 7...9, &:pattern)
      assert_location(ArrayPatternNode, "foo => Foo[]", 7...12, &:pattern)
      assert_location(ArrayPatternNode, "foo => Foo[bar]", 7...15, &:pattern)
    end

    def test_AssocNode
      assert_location(AssocNode, "{ '': 1 }", 2...7) { |node| node.elements.first }
      assert_location(AssocNode, "{ foo: :bar }", 2...11) { |node| node.elements.first }
      assert_location(AssocNode, "{ :foo => :bar }", 2...14) { |node| node.elements.first }
      assert_location(AssocNode, "foo(bar: :baz)", 4...13) { |node| node.arguments.arguments.first.elements.first }
    end

    def test_unconsumed_error_recovery_locations
      ["{not %", "{not   ", "{not \x01", "alias   ", "undef   ", "case x; in [   ", "case x; in a |   "].each do |source|
        result = Ruby::Prism.parse(source)
        assert_predicate result, :failure?

        nodes = [result.value]
        until nodes.empty?
          node = nodes.pop
          location = node.location
          assert_operator location.start_offset, :>=, 0, source.inspect
          assert_operator location.end_offset, :<=, source.bytesize, source.inspect
          assert_operator location.length, :>=, 0, source.inspect
          nodes.concat(node.compact_child_nodes)
        end
      end

      assoc = Ruby::Prism.parse_statement("{not %").receiver.elements.first
      assert_equal 4, assoc.location.start_offset
      assert_equal 0, assoc.location.length
      assert_equal 4, assoc.key.location.start_offset
      assert_equal 0, assoc.key.location.length
    end

    def test_AssocSplatNode
      assert_location(AssocSplatNode, "{ **foo }", 2...7) { |node| node.elements.first }
      assert_location(AssocSplatNode, "foo(**bar)", 4...9) { |node| node.arguments.arguments.first.elements.first }
    end

    def test_BackReferenceReadNode
      assert_location(BackReferenceReadNode, "$+")
    end

    def test_BeginNode
      assert_location(BeginNode, "begin foo end")
      assert_location(BeginNode, "begin foo rescue bar end")
      assert_location(BeginNode, "begin foo; rescue bar\nelse baz end")
      assert_location(BeginNode, "begin foo; rescue bar\nelse baz\nensure qux end")

      assert_location(BeginNode, "class Foo\nrescue then end", 0..25, &:body)
      assert_location(BeginNode, "module Foo\nrescue then end", 0..26, &:body)
    end

    def test_BlockArgumentNode
      assert_location(BlockArgumentNode, "foo(&bar)", 4...8, &:block)
    end

    def test_BlockLocalVariableNode
      assert_location(BlockLocalVariableNode, "foo { |;bar| }", 8...11) do |node|
        node.block.parameters.locals.first
      end
    end

    def test_BlockNode
      assert_location(BlockNode, "foo {}", 4...6, &:block)
      assert_location(BlockNode, "foo do end", 4...10, &:block)
    end

    def test_BlockParameterNode
      assert_location(BlockParameterNode, "def foo(&bar) end", 8...12) { |node| node.parameters.block }
    end

    def test_BlockParametersNode
      assert_location(BlockParametersNode, "foo { || }", 6...8) { |node| node.block.parameters }
      assert_location(BlockParametersNode, "foo { |bar| baz }", 6...11) { |node| node.block.parameters }
      assert_location(BlockParametersNode, "foo { |bar; baz| baz }", 6...16) { |node| node.block.parameters }

      assert_location(BlockParametersNode, "-> () {}", 3...5, &:parameters)
      assert_location(BlockParametersNode, "-> (bar) { baz }", 3...8, &:parameters)
      assert_location(BlockParametersNode, "-> (bar; baz) { baz }", 3...13, &:parameters)
    end

    def test_BreakNode
      assert_location(BreakNode, "tap { break }", 6...11) { |node| node.block.body.body.first }
      assert_location(BreakNode, "tap { break foo }", 6...15) { |node| node.block.body.body.first }
      assert_location(BreakNode, "tap { break foo, bar }", 6...20) { |node| node.block.body.body.first }
      assert_location(BreakNode, "tap { break(foo) }", 6...16) { |node| node.block.body.body.first }
    end

    def test_CallNode
      assert_location(CallNode, "foo")
      assert_location(CallNode, "foo?")
      assert_location(CallNode, "foo!")

      assert_location(CallNode, "foo()")
      assert_location(CallNode, "foo?()")
      assert_location(CallNode, "foo!()")

      assert_location(CallNode, "foo(bar)")
      assert_location(CallNode, "foo?(bar)")
      assert_location(CallNode, "foo!(bar)")

      assert_location(CallNode, "!foo")
      assert_location(CallNode, "~foo")
      assert_location(CallNode, "+foo")
      assert_location(CallNode, "-foo")

      assert_location(CallNode, "not foo")
      assert_location(CallNode, "not(foo)")
      assert_location(CallNode, "not()")

      assert_location(CallNode, "foo + bar")
      assert_location(CallNode, "foo -\n  bar")

      assert_location(CallNode, "Foo()")
      assert_location(CallNode, "Foo(bar)")

      assert_location(CallNode, "Foo::Bar()")
      assert_location(CallNode, "Foo::Bar(baz)")

      assert_location(CallNode, "Foo::bar")
      assert_location(CallNode, "Foo::bar()")
      assert_location(CallNode, "Foo::bar(baz)")

      assert_location(CallNode, "Foo.bar")
      assert_location(CallNode, "Foo.bar()")
      assert_location(CallNode, "Foo.bar(baz)")

      assert_location(CallNode, "foo::bar")
      assert_location(CallNode, "foo::bar()")
      assert_location(CallNode, "foo::bar(baz)")

      assert_location(CallNode, "foo.bar")
      assert_location(CallNode, "foo.bar()")
      assert_location(CallNode, "foo.bar(baz)")

      assert_location(CallNode, "foo&.bar")
      assert_location(CallNode, "foo&.bar()")
      assert_location(CallNode, "foo&.bar(baz)")

      assert_location(CallNode, "foo[]")
      assert_location(CallNode, "foo[bar]")
      assert_location(CallNode, "foo[bar, baz]")

      assert_location(CallNode, "foo[] = 1")
      assert_location(CallNode, "foo[bar] = 1")
      assert_location(CallNode, "foo[bar, baz] = 1")

      assert_location(CallNode, "foo.()")
      assert_location(CallNode, "foo.(bar)")

      assert_location(CallNode, "foo&.()")
      assert_location(CallNode, "foo&.(bar)")

      assert_location(CallNode, "foo::()")
      assert_location(CallNode, "foo::(bar)")
      assert_location(CallNode, "foo::(bar, baz)")

      assert_location(CallNode, "foo bar baz")
      assert_location(CallNode, "foo bar('baz')")
    end

    def test_CallAndWriteNode
      assert_location(CallAndWriteNode, "foo.foo &&= bar")
    end

    def test_CallOperatorWriteNode
      assert_location(CallOperatorWriteNode, "foo.foo += bar")
    end

    def test_CallOrWriteNode
      assert_location(CallOrWriteNode, "foo.foo ||= bar")
    end

    def test_CallTargetNode
      assert_location(CallTargetNode, "foo.bar, = baz", 0...7) do |node|
        node.lefts.first
      end
    end

    def test_CapturePatternNode
      assert_location(CapturePatternNode, "case foo; in bar => baz; end", 13...23) do |node|
        node.conditions.first.pattern
      end
    end

    def test_CaseNode
      assert_location(CaseNode, "case foo; when bar; end")
      assert_location(CaseNode, "case foo; when bar; else; end")
      assert_location(CaseNode, "case foo; when bar; when baz; end")
      assert_location(CaseNode, "case foo; when bar; when baz; else; end")
    end

    def test_CaseMatchNode
      assert_location(CaseMatchNode, "case foo; in bar; end")
      assert_location(CaseMatchNode, "case foo; in bar; else; end")
      assert_location(CaseMatchNode, "case foo; in bar; in baz; end")
      assert_location(CaseMatchNode, "case foo; in bar; in baz; else; end")
    end

    def test_case_match_predicate_before_in_clause
      assert_location(MatchPredicateNode, "case 1 in 2 in true; 3; end", 5...11) do |node|
        node.predicate
      end

      assert_location(MatchPredicateNode, "case not 1 in 2 in false; 3; end", 9...15) do |node|
        node.predicate.receiver
      end

      assert_location(MatchPredicateNode, "case 1 and 1 in 2 in true; 3; end", 11...17) do |node|
        node.predicate.right
      end

      ["1 or not value in P", "(value in P) in Q", "not(value in P) in Q", "value && other in P", "!f x do end"].each do |predicate|
        result = Ruby::Prism.parse("case #{predicate} in Integer; :body; end")
        assert_predicate result, :success?, predicate
        assert_equal predicate, result.statement.predicate.slice
        assert_equal ["Integer"], result.statement.conditions.map { |clause| clause.pattern.slice }
      end

      assert_false Ruby::Prism.parse_success?("case !f x do end in P in Q; :body; end")
    end

    def test_command_calls_with_blocks_before_in_clause
      [
        "f &blk", "obj.f &blk", "obj.f(&blk) in Integer", "obj.f x do end.tail",
        "super &blk", "super(&blk) in Integer", "super do end in Integer", "super x do end.tail"
      ].each do |predicate|
        result = Ruby::Prism.parse("case #{predicate} in P; :body; end")
        assert_predicate result, :success?, predicate
        assert_equal predicate, result.statement.predicate.slice
        assert_equal ["P"], result.statement.conditions.map { |clause| clause.pattern.slice }
      end
    end

    def test_match_in_case_clause_body
      assert_location(MatchPredicateNode, "case 1; in 1; 2 in 2 in true; 3; end", 14...20) do |node|
        assert_equal 2, node.conditions.length
        node.conditions.first.statements.body.first
      end

      assert_location(MatchPredicateNode, "case 1; in 1; 1 + 2 in 3; end", 14...24) do |node|
        assert_equal 1, node.conditions.length
        node.conditions.first.statements.body.first
      end

      assert_location(MatchPredicateNode, "case 1; in 1; a.b = 1 in 1; end", 14...26) do |node|
        assert_equal 1, node.conditions.length
        node.conditions.first.statements.body.first
      end
    end

    def test_operator_call_before_an_in_clause
      source = "case v; in A; lhs + rhs in B in C; tail; end"
      assert_location(MatchPredicateNode, source, source.index("lhs")...source.index(" in C")) do |node|
        assert_equal ["A", "C"], node.conditions.map { |clause| clause.pattern.slice }
        match = node.conditions.first.statements.body.first
        assert_equal :+, match.value.name
        match
      end

      source = "case v; in A; lhs.+ rhs in B then tail; end"
      assert_location(CallNode, source, source.index("lhs")...source.index(" in B")) do |node|
        assert_equal ["A", "B"], node.conditions.map { |clause| clause.pattern.slice }
        call = node.conditions.first.statements.body.first
        assert_equal :+, call.name
        call
      end
    end

    def test_match_in_a_modifier_predicate_before_an_in_clause
      %w[if unless while until].each do |modifier|
        source = "case v; in A; work #{modifier} lhs + rhs in B in C; tail; end"
        assert_location(MatchPredicateNode, source, source.index("lhs")...source.index(" in C")) do |node|
          assert_equal ["A", "C"], node.conditions.map { |clause| clause.pattern.slice }
          node.conditions.first.statements.body.first.predicate
        end
      end
    end

    def test_do_block_in_case_clause_inside_command_arguments
      ["when ready then", "value; when ready then", "value; when ready; else", "value; in Integer then", "value; in Integer; else"].each do |clause|
        source = "receive case #{clause} produce do :ok end end"
        block = "do :ok end"
        start = source.index(block)
        assert_location(BlockNode, source, start...(start + block.length)) do |outer|
          assert_nil outer.block
          case_node = outer.arguments.arguments.first
          branch = case_node.else_clause || case_node.conditions.first
          call = branch.statements.body.first
          assert_equal :produce, call.name
          call.block
        end
      end
    end

    def test_do_blocks_on_case_branches_and_the_enclosing_command
      source = "receive case value; in Integer then Produce do :first end; else collect item (x) {} do :second end; end do :outer end"
      result = Ruby::Prism.parse(source)
      assert_predicate result, :success?

      receive = result.statement
      assert_equal "do :outer end", receive.block.slice
      case_node = receive.arguments.arguments.first
      produce = case_node.conditions.first.statements.body.first
      assert_equal :Produce, produce.name
      assert_equal "do :first end", produce.block.slice
      collect = case_node.else_clause.statements.body.first
      assert_equal :collect, collect.name
      item = collect.arguments.arguments.first
      assert_equal :item, item.name
      assert_equal "{}", item.block.slice
      assert_equal "do :second end", collect.block.slice
    end

    def test_return_before_case_in_clause
      assert_location(ReturnNode, "def f; case 1; in 1; return :empty in 2; :two; end; end", 21...34) do |node|
        case_node = node.body.body.first
        assert_equal 2, case_node.conditions.length
        case_node.conditions.first.statements.body.first
      end
    end

    def test_loop_jump_before_case_in_clause
      { "break" => BreakNode, "next" => NextNode }.each do |keyword, kind|
        jump = "#{keyword} :empty"
        source = "loop { case 1; in 1; #{jump} in 2; :two; end }"
        assert_location(kind, source, source.index(jump)...source.index(" in 2")) do |node|
          case_node = node.block.body.body.first
          assert_equal 2, case_node.conditions.length
          case_node.conditions.first.statements.body.first
        end
      end
    end

    def test_empty_parentheses_are_a_jump_argument_before_an_in_clause
      %w[return break next].each do |keyword|
        source = "loop { case x; in A; #{keyword}() in B; end }"
        start = source.index("(")
        assert_location(ParenthesesNode, source, start...(start + 2)) do |node|
          case_node = node.block.body.body.first
          assert_equal 2, case_node.conditions.length
          jump = case_node.conditions.first.statements.body.first
          assert_equal keyword, jump.keyword
          jump.arguments.arguments.first
        end
      end
    end

    def test_multiple_assignment_in_rescue_before_case_in_clause
      source = "case x; in 1; f rescue *xs = m 1 in 2; end"
      assert_location(MultiWriteNode, source, 23...32) do |node|
        assert_equal 2, node.conditions.size
        node.conditions.first.statements.body.first.rescue_expression
      end

      ["work", "x = y = f 1 rescue a"].each do |body|
        source = "case x; in First; #{body} rescue u, v = values in Second; tail; end"
        assert_location(MultiWriteNode, source, source.index("u, v")...source.index(" in Second")) do |node|
          assert_equal ["First", "Second"], node.conditions.map { |clause| clause.pattern.slice }
          assert_equal "tail", node.conditions.last.statements.body.first.slice
          node.conditions.first.statements.body.first.rescue_expression
        end
      end

      source = "case x; in First; work rescue u = values in Second; end"
      assert_location(MatchPredicateNode, source, source.index("u =")...source.index("; end")) do |node|
        assert_equal 1, node.conditions.size
        node.conditions.first.statements.body.first.rescue_expression
      end
    end

    def test_multiple_assignment_in_rescue_before_if_modifier
      ["obj.tail", "(f y do end).tail", "obj[0]", "A::B", "(a, b)", "*items"].each do |target|
        source = "work rescue #{target}, z = values if ready"
        assert_location(MultiWriteNode, source, source.index(target)...source.index(" if ready")) do |modifier|
          assert_instance_of IfNode, modifier
          modifier.statements.body.first.rescue_expression
        end
      end
    end

    def test_block_call_as_rescue_handler
      source = "work rescue f y do end.tail"
      assert_location(CallNode, source, source.index("f y")...source.length, &:rescue_expression)
    end

    def test_pattern_match_in_a_rescue_handler
      { "in" => MatchPredicateNode, "=>" => MatchRequiredNode }.each do |operator, kind|
        source = "work rescue value #{operator} Integer"
        assert_location(kind, source, source.index("value")...source.length, &:rescue_expression)

        source = "x = work rescue value #{operator} Integer"
        assert_location(kind, source) do |match|
          assert_instance_of LocalVariableWriteNode, match.value
          assert_instance_of RescueModifierNode, match.value.value
          match
        end
      end
    end

    def test_case_clause_after_a_rescue_handler_ending_in_a_match
      handler = "not value in P"
      source = "case x; in C; work rescue #{handler} in Q; ok; end"
      assert_location(CallNode, source, source.index(handler)...source.index(" in Q")) do |node|
        assert_equal 2, node.conditions.length
        call = node.conditions.first.statements.body.first.rescue_expression
        assert_instance_of MatchPredicateNode, call.receiver
        call
      end
    end

    def test_in_after_nested_assignment
      assert_location(LocalVariableWriteNode, "case v; in 0; x = y = f 1 in 2; end", 14...25) do |node|
        assert_equal 2, node.conditions.size
        node.conditions.first.statements.body.first
      end

      assert_location(MatchPredicateNode, "case v; in 0; x = y = f(1) in 2; end", 14...31) do |node|
        assert_equal 1, node.conditions.size
        node.conditions.first.statements.body.first
      end
    end

    def test_assignment_comma_after_a_call_with_a_brace_block
      ["f(v) {}", "(f (v) {})"].each do |first|
        source = "x = #{first}, z"
        assert_location(ArrayNode, source, 4...source.length) do |write|
          assert_equal [first, "z"], write.value.elements.map(&:slice)
          write.value
        end
      end

      source = "x = f v {}, z"
      assert_location(CallNode, source, 4...source.length) do |write|
        assert_equal ["v {}", "z"], write.value.arguments.arguments.map(&:slice)
        write.value
      end
    end

    def test_nested_command_assignment_registers_targets_before_the_call
      source = "x = y ||= f x, y if ready"
      assert_location(CallNode, source, 10...16) do |modifier|
        assert_instance_of IfNode, modifier
        write = modifier.statements.body.first
        assert_instance_of LocalVariableWriteNode, write
        assert_instance_of LocalVariableOrWriteNode, write.value
        call = write.value.value
        assert_equal [:x, :y], call.arguments.arguments.map(&:name)
        call.arguments.arguments.each { |argument| assert_instance_of LocalVariableReadNode, argument }
        call
      end
    end

    def test_nested_assignment_as_first_value_of_a_multiple_rhs
      [
        "y = f(1) rescue 2", "(y = f 1 rescue 2)", "@y = (table[:k] = f 1 rescue 2)",
        "y ||= f(1) rescue 2", "(obj.value &&= f 1 rescue 2)", "table[:k] += f(1) rescue 2",
        "y ||= (@z <<= f 1 rescue 2)"
      ].each do |first|
        source = "x = #{first}, z"
        assert_location(ArrayNode, source, 4...source.length) do |write|
          assert_equal [first, "z"], write.value.elements.map(&:slice)
          write.value
        end
      end
    end

    def test_rescue_inside_bare_not_in_endless_def
      assert_location(RescueModifierNode, "def f = not a rescue b rescue c", 12...31) do |node|
        receiver = node.body.body.first.receiver
        assert_instance_of RescueModifierNode, receiver.expression
        receiver
      end

      assert_location(RescueModifierNode, "def f = not not a rescue b", 16...26) do |node|
        node.body.body.first.receiver.receiver
      end

      assert_location(RescueModifierNode, "def f = not (a) rescue b", 12...24) do |node|
        node.body.body.first.receiver
      end

      assert_location(RescueModifierNode, "def f = not(a) rescue b", 8...23) do |node|
        node.body.body.first
      end

      source = "def f = not return rescue retry rescue return"
      assert_location(RescueModifierNode, source, source.index("return")...source.length, version: "3.3") do |node|
        node.body.body.first.receiver
      end
    end

    def test_bare_not_with_a_command_and_rescue_in_an_endless_def
      source = "def f = not work 1 rescue recover do :ok end"
      assert_location(RescueModifierNode, source, source.index("work")...source.length) do |node|
        rescue_node = node.body.body.first.receiver
        assert_equal "work 1", rescue_node.expression.slice
        assert_equal "do :ok end", rescue_node.rescue_expression.block.slice
        rescue_node
      end
    end

    def test_pattern_match_after_endless_def_with_not
      assert_location(DefNode, "def check = not 1 in 2", 0...17) do |node|
        assert_instance_of MatchPredicateNode, node
        node.value
      end

      assert_location(DefNode, "def tag = not 1 => bound", 0...15) do |node|
        assert_instance_of MatchRequiredNode, node
        node.value
      end
    end

    def test_call_on_jump_with_command_block
      %w[return break next].each do |keyword|
        source = "loop { x = #{keyword} m 1 do end.g }"
        start = source.index(keyword)
        assert_location(CallNode, source, start...source.index(" }")) do |node|
          call = node.block.body.body.first.value
          jump = call.receiver
          assert_equal keyword, jump.keyword
          assert_instance_of BlockNode, jump.arguments.arguments.first.block
          assert_equal :g, call.name
          call
        end
      end
    end

    def test_call_on_a_parenthesized_method_in_a_jump_argument
      %w[return break next].each do |keyword|
        source = "loop { #{keyword} m(1) do end.g }"
        assert_location(CallNode, source, source.index("m(1)")...source.index(" }")) do |node|
          jump = node.block.body.body.first
          assert_equal keyword, jump.keyword
          call = jump.arguments.arguments.first
          assert_equal :g, call.name
          assert_equal :m, call.receiver.name
          assert_instance_of BlockNode, call.receiver.block
          call
        end
      end
    end

    def test_shorthand_after_a_constant_named_command_with_a_do_block
      [".", "&.", "::"].each do |operator|
        source = "C::F x do end#{operator}()"
        assert_location(CallNode, source, version: "4.0") do |call|
          assert_equal :call, call.name
          assert_equal :F, call.receiver.name
          assert_equal "do end", call.receiver.block.slice
          call
        end
      end
    end

    def test_grouping_a_block_call_receiver
      assert_location(CallNode, "C::F x do end::G") do |call|
        assert_equal :G, call.name
        call
      end
      assert_location(ConstantPathNode, "(C::F x do end)::G")
      assert_location(MultiWriteNode, "(C::F x do end).tail, y = z")

      source = "outer(C::F x do end.tail)"
      assert_location(CallNode, source, source.index("C::F")...source.index(")"), version: "3.4") do |outer|
        outer.arguments.arguments.fetch(0)
      end
    end

    def test_operator_after_a_grouped_expression_ending_in_a_block_call
      ["!f x do end.tail", "not f x do end.tail", "a and f x do end.tail", "a or f x do end.tail"].each do |expression|
        assert_location(CallNode, "(#{expression}) + y") do |call|
          assert_equal :+, call.name
          assert_instance_of ParenthesesNode, call.receiver
          call
        end
      end
    end

    def test_constant_method_after_command_block
      source = "m case f 1 do end::C in 2; end"
      assert_location(CallNode, source, source.index("f 1")...source.index(" in")) do |node|
        predicate = node.arguments.arguments.first.predicate
        assert_equal :C, predicate.name
        assert_instance_of BlockNode, predicate.receiver.block
        predicate
      end
    end

    def test_do_block_after_an_argument_with_a_brace_block
      ["inner(x) {}", "A::B() {}", "A.B {}", "A::b {}", "inner A::B {}"].each do |argument|
        assert_location(CallNode, "outer #{argument} do end") do |outer|
          assert_equal argument, outer.arguments.arguments.first.slice
          assert_equal "do end", outer.block.slice
          outer
        end
      end

      assert_location(CallNode, "m x do end::B {}.tail") do |call|
        assert_equal :tail, call.name
        assert_equal "{}", call.receiver.block.slice
        call
      end
    end

    def test_do_block_on_a_call_with_an_endless_method_argument
      ["super A::B() {}", "inner mid g (x) {}", "return inner A::B() {}"].each do |body|
        assert_location(CallNode, "outer def f = #{body} do end", version: "4.0") do |outer|
          assert_equal "do end", outer.block.slice
          assert_equal body, outer.arguments.arguments.first.body.body.first.slice
          outer
        end
      end

      source = "outer def f = super A::B {} rescue fallback do end"
      assert_location(CallNode, source, version: "4.0") do |outer|
        assert_nil outer.block
        rescue_modifier = outer.arguments.arguments.first.body.body.first
        assert_equal "do end", rescue_modifier.rescue_expression.block.slice
        outer
      end
    end

    def test_endless_definitions_with_braced_calls_as_arguments
      assert_location(CallNode, "outer def f = g (x) {}", version: "4.0") do |outer|
        assert_equal ["def f = g (x) {}"], outer.arguments.arguments.map(&:slice)
        outer
      end

      source = "outer def f = g(x) {} rescue a do end, z"
      assert_location(CallNode, source, version: "4.0") do |outer|
        definition, tail = outer.arguments.arguments
        body = definition.body.body.first
        assert_equal "g(x) {}", body.expression.slice
        assert_equal "do end", body.rescue_expression.block.slice
        assert_equal "z", tail.slice
        outer
      end
    end

    def test_case_clause_after_an_endless_definition_with_a_brace_command_body
      source = "case v; in 0; def f = g (x) {} in Integer; end"
      assert_location(CaseMatchNode, source) do |node|
        first, second = node.conditions
        assert_equal "def f = g (x) {}", first.statements.body.first.slice
        assert_equal "Integer", second.pattern.slice
        node
      end
    end

    def test_rescue_after_nested_command_assignment
      source = "targets[:k] = tmp = call_boom 1 rescue nil rescue :outer"
      assert_location(RescueModifierNode, source) do |node|
        write = node.expression.arguments.arguments.last
        assert_instance_of LocalVariableWriteNode, write
        assert_instance_of RescueModifierNode, write.value
        node
      end
    end

    def test_second_rescue_through_three_assignment_targets
      source = "x = y = z ||= f(1) rescue a rescue b"
      assert_location(RescueModifierNode, source, source.index("z ||=")...source.length) do |x_write|
        rescue_node = x_write.value.value
        assert_equal "z ||= f(1) rescue a", rescue_node.expression.slice
        rescue_node
      end

      source = "x = y = z ||= f 1 rescue a rescue b"
      assert_location(RescueModifierNode, source) do |rescue_node|
        assert_equal "x = y = z ||= f 1 rescue a", rescue_node.expression.slice
        rescue_node
      end
    end

    def test_second_rescue_after_nested_operator_writes
      source = "x &&= y += f 1 rescue a rescue b and ok"
      assert_location(RescueModifierNode, source) do |node|
        assert_equal "x &&= y += f 1 rescue a", node.expression.slice
        assert_instance_of AndNode, node.rescue_expression
        assert_equal "b and ok", node.rescue_expression.slice
        node
      end

      source = "x &&= (y += f 1 rescue a) rescue b and ok"
      assert_location(AndNode, source) do |node|
        assert_instance_of LocalVariableAndWriteNode, node.left
        assert_equal "(y += f 1 rescue a) rescue b", node.left.value.slice
        node
      end

      source = "x = y ||= f 1 rescue a rescue u, v = values"
      assert_location(MultiWriteNode, source, source.index("u, v")...source.length) do |node|
        assert_instance_of RescueModifierNode, node
        node.rescue_expression
      end
    end

    def test_match_in_assignment_rescue_before_case_clause
      source = "case v; in First; x = y = f (v) {} rescue a in Integer in Second; end"
      assert_location(CaseMatchNode, source) do |node|
        assert_equal ["First", "Second"], node.conditions.map { |clause| clause.pattern.slice }
        handler = node.conditions.first.statements.body.first.value.value.rescue_expression
        assert_instance_of MatchPredicateNode, handler
        assert_equal "a in Integer", handler.slice
        node
      end
    end

    def test_rescue_after_a_brace_call_in_multiple_assignment
      assert_location(RescueModifierNode, "a, b = f (v) {} rescue c") do |node|
        assert_instance_of MultiWriteNode, node.expression
        assert_equal "f (v) {}", node.expression.value.slice
        node
      end

      assert_location(MultiWriteNode, "a, b = f(v) {} rescue c") do |node|
        assert_instance_of RescueModifierNode, node.value
        assert_equal "f(v) {}", node.value.expression.slice
        node
      end
    end

    def test_ClassNode
      assert_location(ClassNode, "class Foo end")
      assert_location(ClassNode, "class Foo < Bar; end")
    end

    def test_ClassVariableAndWriteNode
      assert_location(ClassVariableAndWriteNode, "@@foo &&= bar")
    end

    def test_ClassVariableOperatorWriteNode
      assert_location(ClassVariableOperatorWriteNode, "@@foo += bar")
    end

    def test_ClassVariableOrWriteNode
      assert_location(ClassVariableOrWriteNode, "@@foo ||= bar")
    end

    def test_ClassVariableReadNode
      assert_location(ClassVariableReadNode, "@@foo")
    end

    def test_ClassVariableTargetNode
      assert_location(ClassVariableTargetNode, "@@foo, @@bar = baz", 0...5) do |node|
        node.lefts.first
      end
    end

    def test_ClassVariableWriteNode
      assert_location(ClassVariableWriteNode, "@@foo = bar")
    end

    def test_ConstantPathAndWriteNode
      assert_location(ConstantPathAndWriteNode, "Parent::Child &&= bar")
    end

    def test_ConstantPathNode
      assert_location(ConstantPathNode, "Foo::Bar")
      assert_location(ConstantPathNode, "::Foo")
      assert_location(ConstantPathNode, "::Foo::Bar")
    end

    def test_ConstantPathOperatorWriteNode
      assert_location(ConstantPathOperatorWriteNode, "Parent::Child += bar")
    end

    def test_ConstantPathOrWriteNode
      assert_location(ConstantPathOrWriteNode, "Parent::Child ||= bar")
    end

    def test_ConstantPathTargetNode
      assert_location(ConstantPathTargetNode, "::Foo, ::Bar = baz", 0...5) do |node|
        node.lefts.first
      end
    end

    def test_ConstantPathWriteNode
      assert_location(ConstantPathWriteNode, "Foo::Bar = baz")
      assert_location(ConstantPathWriteNode, "::Foo = bar")
      assert_location(ConstantPathWriteNode, "::Foo::Bar = baz")
    end

    def test_ConstantAndWriteNode
      assert_location(ConstantAndWriteNode, "Foo &&= bar")
    end

    def test_ConstantOperatorWriteNode
      assert_location(ConstantOperatorWriteNode, "Foo += bar")
    end

    def test_ConstantOrWriteNode
      assert_location(ConstantOrWriteNode, "Foo ||= bar")
    end

    def test_ConstantReadNode
      assert_location(ConstantReadNode, "Foo")
    end

    def test_ConstantTargetNode
      assert_location(ConstantTargetNode, "Foo, Bar = baz", 0...3) do |node|
        node.lefts.first
      end
    end

    def test_ConstantWriteNode
      assert_location(ConstantWriteNode, "Foo = bar")
    end

    def test_DefNode
      assert_location(DefNode, "def foo; bar; end")
      assert_location(DefNode, "def foo = bar")
      assert_location(DefNode, "def foo.bar; baz; end")
      assert_location(DefNode, "def foo.bar = baz")
    end

    def test_DefinedNode
      assert_location(DefinedNode, "defined? foo")
      assert_location(DefinedNode, "defined?(foo)")
    end

    def test_ElseNode
      assert_location(ElseNode, "if foo; bar; else; baz; end", 13...27, &:subsequent)
      assert_location(ElseNode, "foo ? bar : baz", 10...15, &:subsequent)
    end

    def test_EmbeddedStatementsNode
      assert_location(EmbeddedStatementsNode, '"foo #{bar} baz"', 5...11) { |node| node.parts[1] }
    end

    def test_EmbeddedVariableNode
      assert_location(EmbeddedVariableNode, '"foo #@@bar baz"', 5...11) { |node| node.parts[1] }
    end

    def test_EnsureNode
      assert_location(EnsureNode, "begin; foo; ensure; bar; end", 12...28, &:ensure_clause)
    end

    def test_FalseNode
      assert_location(FalseNode, "false")
    end

    def test_FindPatternNode
      assert_location(FindPatternNode, "case foo; in *, bar, *; end", 13...22) do |node|
        node.conditions.first.pattern
      end
    end

    def test_FlipFlopNode
      assert_location(FlipFlopNode, "if foo..bar; end", 3..11, &:predicate)

      ["f(...x ? 1 : 2)", "f(y, ...x ? 1 : 2)", "super(...x ? 1 : 2)"].each do |source|
        start = source.index("...")
        assert_location(FlipFlopNode, source, start...(start + 4)) do |call|
          conditional = call.arguments.arguments.last
          assert_kind_of IfNode, conditional
          assert_nil conditional.predicate.left
          assert_equal "x", conditional.predicate.right.slice
          assert_predicate conditional.predicate, :exclude_end?
          conditional.predicate
        end
      end
    end

    def test_FloatNode
      assert_location(FloatNode, "0.0")
      assert_location(FloatNode, "1.0")
      assert_location(FloatNode, "1.0e10")
      assert_location(FloatNode, "1.0e-10")
    end

    def test_ForNode
      assert_location(ForNode, "for foo in bar; end")
      assert_location(ForNode, "for foo, bar in baz do end")
      assert_location(MultiTargetNode, "for *x in ary; end", 4...6) do |node|
        assert_instance_of LocalVariableTargetNode, node.index.rest.expression
        node.index
      end
    end

    def test_ForwardingArgumentsNode
      assert_location(ForwardingArgumentsNode, "def foo(...); bar(...); end", 18...21) do |node|
        node.body.body.first.arguments.arguments.first
      end
    end

    def test_ForwardingParameterNode
      assert_location(ForwardingParameterNode, "def foo(...); end", 8...11) do |node|
        node.parameters.keyword_rest
      end

      [[:first], [:first, :second]].each do |posts|
        source = "def f(opt = 1, #{posts.join(", ")}, ...) = first"
        start = source.index("...")
        assert_location(ForwardingParameterNode, source, start...(start + 3)) do |node|
          parameters = node.parameters
          assert_equal [:opt], parameters.optionals.map(&:name)
          assert_equal posts, parameters.posts.map(&:name)
          assert_nil parameters.rest
          parameters.keyword_rest
        end
      end
    end

    def test_forwarding_after_a_destructured_post_parameter
      source = "def self.f opt = 1, (head, *tail), ...; target(...); end"
      start = source.index("...")
      assert_location(ForwardingParameterNode, source, start...(start + 3)) do |definition|
        parameters = definition.parameters
        assert_nil parameters.rest
        assert_equal "(head, *tail)", parameters.posts.fetch(0).slice
        assert_instance_of ForwardingArgumentsNode, definition.body.body.first.arguments.arguments.first
        parameters.keyword_rest
      end
    end

    def test_ForwardingSuperNode
      assert_location(ForwardingSuperNode, "super")
      assert_location(ForwardingSuperNode, "super {}")
    end

    def test_GlobalVariableAndWriteNode
      assert_location(GlobalVariableAndWriteNode, "$foo &&= bar")
    end

    def test_GlobalVariableOperatorWriteNode
      assert_location(GlobalVariableOperatorWriteNode, "$foo += bar")
    end

    def test_GlobalVariableOrWriteNode
      assert_location(GlobalVariableOrWriteNode, "$foo ||= bar")
    end

    def test_GlobalVariableReadNode
      assert_location(GlobalVariableReadNode, "$foo")
    end

    def test_GlobalVariableTargetNode
      assert_location(GlobalVariableTargetNode, "$foo, $bar = baz", 0...4) do |node|
        node.lefts.first
      end
    end

    def test_GlobalVariableWriteNode
      assert_location(GlobalVariableWriteNode, "$foo = bar")
    end

    def test_HashNode
      assert_location(HashNode, "{ foo: 2 }")
      assert_location(HashNode, "{ \nfoo: 2, \nbar: 3 \n}")
    end

    def test_HashPatternNode
      assert_location(HashPatternNode, "case foo; in bar: baz; end", 13...21) do |node|
        node.conditions.first.pattern
      end
    end

    def test_IfNode
      assert_location(IfNode, "if type in 1;elsif type in B;end")
      assert_location(IfNode, "if ((a => k); x); end", version: "4.0")
      assert_location(IfNode, "if ((return if flag); x); end", version: "4.1")
    end

    def test_ImaginaryNode
      assert_location(ImaginaryNode, "1i")
      assert_location(ImaginaryNode, "1ri")
    end

    def test_ImplicitNode
      assert_location(ImplicitNode, "{ foo: }", 2...6) do |node|
        node.elements.first.value
      end

      assert_location(ImplicitNode, "{ Foo: }", 2..6) do |node|
        node.elements.first.value
      end

      assert_location(ImplicitNode, "foo = 1; { foo: }", 11..15) do |node|
        node.elements.first.value
      end
    end

    def test_ImplicitRestNode
      assert_location(ImplicitRestNode, "foo, = bar", 3..4, &:rest)

      assert_location(ImplicitRestNode, "for foo, in bar do end", 7..8) do |node|
        node.index.rest
      end

      assert_location(ImplicitRestNode, "foo { |bar,| }", 10..11) do |node|
        node.block.parameters.parameters.rest
      end

      assert_location(ImplicitRestNode, "foo in [bar,]", 11..12) do |node|
        node.pattern.rest
      end
    end

    def test_InNode
      assert_location(InNode, "case foo; in bar; end", 10...16) do |node|
        node.conditions.first
      end
    end

    def test_label_newline_ends_a_pattern_guard
      %w[if unless].each do |keyword|
        source = "case x; in {} #{keyword} m k:\nwork value:\nnext_value; end"
        assert_location(CaseMatchNode, source) do |node|
          clause = node.conditions.first
          assert_equal "m k:", clause.pattern.predicate.slice
          assert_equal ["work value:\nnext_value"], clause.statements.body.map(&:slice)
          node
        end
      end
    end

    def test_IndexAndWriteNode
      assert_location(IndexAndWriteNode, "foo[foo] &&= bar")
    end

    def test_IndexOperatorWriteNode
      assert_location(IndexOperatorWriteNode, "foo[foo] += bar")
    end

    def test_IndexOrWriteNode
      assert_location(IndexOrWriteNode, "foo[foo] ||= bar")
    end

    def test_IndexTargetNode
      assert_location(IndexTargetNode, "foo[bar], = qux", 0...8) do |node|
        node.lefts.first
      end
    end

    def test_InstanceVariableAndWriteNode
      assert_location(InstanceVariableAndWriteNode, "@foo &&= bar")
    end

    def test_InstanceVariableOperatorWriteNode
      assert_location(InstanceVariableOperatorWriteNode, "@foo += bar")
    end

    def test_InstanceVariableOrWriteNode
      assert_location(InstanceVariableOrWriteNode, "@foo ||= bar")
    end

    def test_InstanceVariableReadNode
      assert_location(InstanceVariableReadNode, "@foo")
    end

    def test_InstanceVariableTargetNode
      assert_location(InstanceVariableTargetNode, "@foo, @bar = baz", 0...4) do |node|
        node.lefts.first
      end
    end

    def test_InstanceVariableWriteNode
      assert_location(InstanceVariableWriteNode, "@foo = bar")
    end

    def test_IntegerNode
      assert_location(IntegerNode, "0")
      assert_location(IntegerNode, "1")
      assert_location(IntegerNode, "1_000")
      assert_location(IntegerNode, "0x1")
      assert_location(IntegerNode, "0x1_000")
      assert_location(IntegerNode, "0b1")
      assert_location(IntegerNode, "0b1_000")
      assert_location(IntegerNode, "0o1")
      assert_location(IntegerNode, "0o1_000")
    end

    def test_InterpolatedMatchLastLineNode
      assert_location(InterpolatedMatchLastLineNode, "if /foo \#{bar}/ then end", 3...15, &:predicate)
    end

    def test_InterpolatedRegularExpressionNode
      assert_location(InterpolatedRegularExpressionNode, "/\#{foo}/")
      assert_location(InterpolatedRegularExpressionNode, "/\#{foo}/io")
    end

    def test_InterpolatedStringNode
      assert_location(InterpolatedStringNode, "\"foo \#@bar baz\"")
      assert_location(InterpolatedStringNode, "<<~A\nhello \#{1} world\nA", 0...4)
      assert_location(InterpolatedStringNode, '"foo" "bar"')
    end

    def test_InterpolatedSymbolNode
      assert_location(InterpolatedSymbolNode, ':"#{foo}bar"')
    end

    def test_interpolated_symbol_array_locations
      ['#{1}#{2}', '#@a#@b', '#{1}#@a', '#@a#{1}', 'a#{1}#{2}', '#{1}a#{2}'].each do |element|
        source = "%I[#{element} second]"
        result = Ruby::Prism.parse(source)
        assert_predicate result, :success?

        array = result.value.statements.body.first
        symbol, second = array.elements
        assert_kind_of InterpolatedSymbolNode, symbol
        assert_equal 3, symbol.location.start_offset
        assert_equal 3 + element.bytesize, symbol.location.end_offset
        assert_equal element, symbol.location.slice
        assert_equal "second", second.location.slice
        assert_equal source, array.location.slice
      end
    end

    def test_InterpolatedXStringNode
      assert_location(InterpolatedXStringNode, '`foo #{bar} baz`')
    end

    def test_ItLocalVariableReadNode
      assert_location(ItLocalVariableReadNode, "-> { it }", 5...7, version: "3.4.0") do |node|
        node.body.body.first
      end

      assert_location(ItLocalVariableReadNode, "foo { it }", 6...8, version: "3.4.0") do |node|
        node.block.body.body.first
      end

      assert_location(CallNode, "-> { it }", 5...7, version: "3.3.0") do |node|
        node.body.body.first
      end
    end

    def test_ItParametersNode
      assert_location(ItParametersNode, "-> { it }", version: "3.4.0", &:parameters)
    end

    def test_KeywordHashNode
      assert_location(KeywordHashNode, "foo(a, b: 1)", 7...11) { |node| node.arguments.arguments[1] }
    end

    def test_KeywordRestParameterNode
      assert_location(KeywordRestParameterNode, "def foo(**); end", 8...10) do |node|
        node.parameters.keyword_rest
      end

      assert_location(KeywordRestParameterNode, "def foo(**bar); end", 8...13) do |node|
        node.parameters.keyword_rest
      end
    end

    def test_LambdaNode
      assert_location(LambdaNode, "-> { foo }")
      assert_location(LambdaNode, "-> do foo end")
    end

    def test_LocalVariableAndWriteNode
      assert_location(LocalVariableAndWriteNode, "foo &&= bar")
      assert_location(LocalVariableAndWriteNode, "foo = 1; foo &&= bar", 9...20)
    end

    def test_LocalVariableOperatorWriteNode
      assert_location(LocalVariableOperatorWriteNode, "foo += bar")
      assert_location(LocalVariableOperatorWriteNode, "foo = 1; foo += bar", 9...19)
    end

    def test_LocalVariableOrWriteNode
      assert_location(LocalVariableOrWriteNode, "foo ||= bar")
      assert_location(LocalVariableOrWriteNode, "foo = 1; foo ||= bar", 9...20)
    end

    def test_LocalVariableReadNode
      assert_location(LocalVariableReadNode, "foo = 1; foo", 9...12)
    end

    def test_LocalVariableTargetNode
      assert_location(LocalVariableTargetNode, "foo, bar = baz", 0...3) do |node|
        node.lefts.first
      end
    end

    def test_LocalVariableWriteNode
      assert_location(LocalVariableWriteNode, "foo = bar")
    end

    def test_MatchLastLineNode
      assert_location(MatchLastLineNode, "if /foo/ then end", 3...8, &:predicate)
    end

    def test_MatchPredicateNode
      assert_location(MatchPredicateNode, "foo in bar")
    end

    def test_match_can_be_followed_by_composition_and_modifiers
      %w[and or].each do |operator|
        result = Ruby::Prism.parse("1 in Integer #{operator} 2 in Numeric")
        assert_predicate result, :success?
        assert_equal "1 in Integer", result.statement.left.slice
        assert_equal "2 in Numeric", result.statement.right.slice
      end

      assert_location(MatchPredicateNode, "1 in Integer if ready", 0...12) do |node|
        node.statements.body.first
      end
    end

    def test_MatchRequiredNode
      assert_location(MatchRequiredNode, "foo => bar")
    end

    def test_MatchWriteNode
      assert_location(MatchWriteNode, "/(?<foo>)/ =~ foo")
    end

    def test_ModuleNode
      assert_location(ModuleNode, "module Foo end")
    end

    def test_MultiTargetNode
      assert_location(MultiTargetNode, "for foo, bar in baz do end", 4...12, &:index)
      assert_location(MultiTargetNode, "foo, (bar, baz) = qux", 5...15) { |node| node.lefts.last }
      assert_location(MultiTargetNode, "def foo((bar)); end", 8...13) do |node|
        node.parameters.requireds.first
      end
    end

    def test_MultiWriteNode
      assert_location(MultiWriteNode, "foo, bar = baz")
      assert_location(MultiWriteNode, "(foo, bar) = baz")
      assert_location(MultiWriteNode, "((foo, bar)) = baz")
    end

    def test_NextNode
      assert_location(NextNode, "tap { next }", 6...10) { |node| node.block.body.body.first }
      assert_location(NextNode, "tap { next foo }", 6...14) { |node| node.block.body.body.first }
      assert_location(NextNode, "tap { next foo, bar }", 6...19) { |node| node.block.body.body.first }
      assert_location(NextNode, "tap { next(foo) }", 6...15) { |node| node.block.body.body.first }
    end

    def test_NilNode
      assert_location(NilNode, "nil")
    end

    def test_NoBlockParameterNode
      assert_location(NoBlockParameterNode, "def foo(&nil); end", 8...12, version: "4.1") { |node| node.parameters.block }
    end

    def test_NoKeywordsParameterNode
      assert_location(NoKeywordsParameterNode, "def foo(**nil); end", 8...13) { |node| node.parameters.keyword_rest }
    end

    def test_NumberedParametersNode
      assert_location(NumberedParametersNode, "-> { _1 }", &:parameters)
      assert_location(NumberedParametersNode, "foo { _1 }", 4...10) { |node| node.block.parameters }
    end

    def test_NumberedReferenceReadNode
      assert_location(NumberedReferenceReadNode, "$1")
    end

    def test_OptionalKeywordParameterNode
      assert_location(OptionalKeywordParameterNode, "def foo(bar: nil); end", 8...16) do |node|
        node.parameters.keywords.first
      end
    end

    def test_OptionalParameterNode
      assert_location(OptionalParameterNode, "def foo(bar = nil); end", 8...17) do |node|
        node.parameters.optionals.first
      end
    end

    def test_block_parameter_default_primaries
      ["defined?(a)", "(defined? a)", "[..1]", "[def f = 1]", "{k: defined? a}", "-2", "(-2**2)"].each do |value|
        ["x = ", "x: "].each do |parameter|
          source = "m { |#{parameter}#{value}| x }"
          result = Ruby::Prism.parse(source)
          assert_predicate result, :success?, source
          default = result.statement.block.parameters.parameters.compact_child_nodes.first.value
          assert_equal value, default.slice
        end
      end
    end

    def test_OrNode
      assert_location(OrNode, "foo || bar")
      assert_location(OrNode, "foo or bar")
    end

    def test_ParametersNode
      assert_location(ParametersNode, "def foo(bar, baz); end", 8...16, &:parameters)
    end

    def test_bare_method_parameters_with_a_trailing_comma
      assert_location(ParametersNode, "def f x,; end", 6...7, version: "4.1") do |node|
        assert_equal [:x], node.parameters.requireds.map(&:name)
        assert_nil node.parameters.rest
        node.parameters
      end

      assert_location(RestParameterNode, "def self.f *xs,; end", 11...14, version: "4.1") { |node| node.parameters.rest }
    end

    def test_ParenthesesNode
      assert_location(ParenthesesNode, "()")
      assert_location(ParenthesesNode, "(foo)")
      assert_location(ParenthesesNode, "foo (bar), baz", 4...9) { |node| node.arguments.arguments.first }
      assert_location(ParenthesesNode, "def (foo).bar; end", 4...9, &:receiver)
    end

    def test_PinnedExpressionNode
      assert_location(PinnedExpressionNode, "foo in ^(bar)", 7...13, &:pattern)
    end

    def test_braced_hash_pattern_allows_a_multiline_label_value_in_a_pin
      pin = "^(m k:\nvalue)"
      source = "def f opt: (x in {key: #{pin}}); end"
      start = source.index(pin)
      assert_location(PinnedExpressionNode, source, start...(start + pin.bytesize)) do |definition|
        match = definition.parameters.keywords.first.value.body.body.first
        match.pattern.elements.first.value
      end
    end

    def test_PinnedVariableNode
      assert_location(PinnedVariableNode, "bar = 1; foo in ^bar", 16...20, &:pattern)
      assert_location(PinnedVariableNode, "proc { 1 in ^it }.call(1)", 12...15, version: "3.4.0") do |node|
        node.receiver.block.body.body.first.pattern
      end
    end

    def test_PostExecutionNode
      assert_location(PostExecutionNode, "END {}")
      assert_location(PostExecutionNode, "END { foo }")
    end

    def test_PreExecutionNode
      assert_location(PreExecutionNode, "BEGIN {}")
      assert_location(PreExecutionNode, "BEGIN { foo }")
    end

    def test_RangeNode
      assert_location(RangeNode, "1..2")
      assert_location(RangeNode, "1...2")

      assert_location(RangeNode, "..2")
      assert_location(RangeNode, "...2")

      assert_location(RangeNode, "1..")
      assert_location(RangeNode, "1...")
    end

    def test_RationalNode
      assert_location(RationalNode, "1r")
      assert_location(RationalNode, "1.0r")
    end

    def test_RedoNode
      assert_location(RedoNode, "tap { redo }", 6...10) { |node| node.block.body.body.first }
    end

    def test_RegularExpressionNode
      assert_location(RegularExpressionNode, "/foo/")
      assert_location(RegularExpressionNode, "/foo/io")
    end

    def test_RequiredKeywordParameterNode
      assert_location(RequiredKeywordParameterNode, "def foo(bar:); end", 8...12) do |node|
        node.parameters.keywords.first
      end
    end

    def test_RequiredParameterNode
      assert_location(RequiredParameterNode, "def foo(bar); end", 8...11) do |node|
        node.parameters.requireds.first
      end
    end

    def test_RescueNode
      code = <<~RUBY
      begin
        body
      rescue TypeError
      rescue ArgumentError
      end
      RUBY
      assert_location(RescueNode, code, 13...50) { |node| node.rescue_clause }
      assert_location(RescueNode, code, 30...50) { |node| node.rescue_clause.subsequent }
    end

    def test_RescueModifierNode
      assert_location(RescueModifierNode, "foo rescue bar")
    end

    def test_RestParameterNode
      assert_location(RestParameterNode, "def foo(*bar); end", 8...12) do |node|
        node.parameters.rest
      end
    end

    def test_RetryNode
      assert_location(RetryNode, "begin; rescue; retry; end", 15...20) { |node| node.rescue_clause.statements.body.first }
    end

    def test_ReturnNode
      assert_location(ReturnNode, "return")
      assert_location(ReturnNode, "return foo")
      assert_location(ReturnNode, "return foo, bar")
      assert_location(ReturnNode, "return(foo)")
    end

    def test_return_in_a_singleton_class_body
      [
        ["-> { class << self; return; end }", "3.3"],
        ["class C; class << self; return; end; end", "3.3"],
        ["def f; -> { class << self; return; end }; end", "4.1"],
        ["class << self; -> { return }; end", "4.1"]
      ].each do |source, version|
        start = source.index("return")
        assert_location(ReturnNode, source, start...(start + 6), version: version) do |node|
          node.breadth_first_search { |child| child.is_a?(ReturnNode) }
        end
      end
    end

    def test_SelfNode
      assert_location(SelfNode, "self")
    end

    def test_ShareableConstantNode
      source = <<~RUBY
        # shareable_constant_value: literal
        C = { foo: 1 }
      RUBY

      assert_location(ShareableConstantNode, source, 36...50)
    end

    def test_SingletonClassNode
      assert_location(SingletonClassNode, "class << self; end")
    end

    def test_SourceEncodingNode
      assert_location(SourceEncodingNode, "__ENCODING__")
    end

    def test_SourceFileNode
      assert_location(SourceFileNode, "__FILE__")
    end

    def test_SourceLineNode
      assert_location(SourceLineNode, "__LINE__")
    end

    def test_SplatNode
      assert_location(SplatNode, "*foo = bar", 0...4, &:rest)
      assert_location(SplatNode, "def f(*) = g *", 13...14) do |definition|
        call = definition.body.body.first
        assert_equal :g, call.name
        splat = call.arguments.arguments.first
        assert_nil splat.expression
        splat
      end
    end

    def test_StatementsNode
      assert_location(StatementsNode, "foo { 1 }", 6...7) { |node| node.block.body }

      assert_location(StatementsNode, "(1)", 1...2, &:body)

      assert_location(StatementsNode, "def foo; 1; end", 9...10, &:body)
      assert_location(StatementsNode, "def foo = 1", 10...11, &:body)
      assert_location(StatementsNode, "def foo; 1\n2; end", 9...12, &:body)

      assert_location(StatementsNode, "if foo; bar; end", 8...11, &:statements)
      assert_location(StatementsNode, "foo if bar", 0...3, &:statements)

      assert_location(StatementsNode, "if foo; foo; elsif bar; bar; end", 24...27) { |node| node.subsequent.statements }
      assert_location(StatementsNode, "if foo; foo; else; bar; end", 19...22) { |node| node.subsequent.statements }

      assert_location(StatementsNode, "unless foo; bar; end", 12...15, &:statements)
      assert_location(StatementsNode, "foo unless bar", 0...3, &:statements)

      assert_location(StatementsNode, "case; when foo; bar; end", 16...19) { |node| node.conditions.first.statements }

      assert_location(StatementsNode, "while foo; bar; end", 11...14, &:statements)
      assert_location(StatementsNode, "foo while bar", 0...3, &:statements)

      assert_location(StatementsNode, "until foo; bar; end", 11...14, &:statements)
      assert_location(StatementsNode, "foo until bar", 0...3, &:statements)

      assert_location(StatementsNode, "for foo in bar; baz; end", 16...19, &:statements)

      assert_location(StatementsNode, "begin; foo; end", 7...10, &:statements)
      assert_location(StatementsNode, "begin; rescue; foo; end", 15...18) { |node| node.rescue_clause.statements }
      assert_location(StatementsNode, "begin; ensure; foo; end", 15...18) { |node| node.ensure_clause.statements }
      assert_location(StatementsNode, "begin; rescue; else; foo; end", 21...24) { |node| node.else_clause.statements }

      assert_location(StatementsNode, "class Foo; foo; end", 11...14, &:body)
      assert_location(StatementsNode, "module Foo; foo; end", 12...15, &:body)
      assert_location(StatementsNode, "class << self; foo; end", 15...18, &:body)

      assert_location(StatementsNode, "-> { foo }", 5...8, &:body)
      assert_location(StatementsNode, "BEGIN { foo }", 8...11, &:statements)
      assert_location(StatementsNode, "END { foo }", 6...9, &:statements)

      assert_location(StatementsNode, "\"\#{foo}\"", 3...6) { |node| node.parts.first.statements }
    end

    def test_StringNode
      assert_location(StringNode, '"foo"')
      assert_location(StringNode, '%q[foo]')
    end

    def test_SuperNode
      assert_location(SuperNode, "super foo")
      assert_location(SuperNode, "super foo, bar")

      assert_location(SuperNode, "super()")
      assert_location(SuperNode, "super(foo)")
      assert_location(SuperNode, "super(foo, bar)")

      assert_location(SuperNode, "super() {}")
    end

    def test_SymbolNode
      assert_location(SymbolNode, ":foo")
    end

    def test_TrueNode
      assert_location(TrueNode, "true")
    end

    def test_UndefNode
      assert_location(UndefNode, "undef foo")
      assert_location(UndefNode, "undef foo, bar")
    end

    def test_UnlessNode
      assert_location(UnlessNode, "foo unless bar")
      assert_location(UnlessNode, "unless bar; foo; end")
    end

    def test_UntilNode
      assert_location(UntilNode, "foo = bar until baz")
      assert_location(UntilNode, "until bar;baz;end")
    end

    def test_WhenNode
      assert_location(WhenNode, "case foo; when bar; end", 10...18) { |node| node.conditions.first }
    end

    def test_WhileNode
      assert_location(WhileNode, "foo = bar while foo != baz")
      assert_location(WhileNode, "while a;bar;baz;end")
    end

    def test_XStringNode
      assert_location(XStringNode, "`foo`")
      assert_location(XStringNode, "%x[foo]")
    end

    def test_YieldNode
      assert_location(YieldNode, "def test; yield; end", 10...15) { |node| node.body.body.first }
      assert_location(YieldNode, "def test; yield foo; end", 10...19) { |node| node.body.body.first }
      assert_location(YieldNode, "def test; yield foo, bar; end", 10...24) { |node| node.body.body.first }
      assert_location(YieldNode, "def test; yield(foo); end", 10...20) { |node| node.body.body.first }
    end

    def test_all_tested
      expected = Ruby::Prism.constants.grep(/.Node$/).sort - %i[ErrorRecoveryNode ProgramNode]
      actual = SourceLocationTest.instance_methods(false).grep(/.Node$/).map { |name| name[5..].to_sym }.sort
      assert_equal expected, actual
    end

    private

    def assert_location(kind, source, expected = 0...source.length, **options)
      result = Ruby::Prism.parse(source, **options)
      assert result.success?

      node = result.value.statements.body.last
      node = yield node if block_given?

      if expected.begin == 0
        assert_equal 0, node.location.start_column, "#{kind} start_column"
      end

      if expected.end == source.length
        assert_equal source.split("\n").last.length, node.location.end_column, "#{kind} end_column"
      end

      assert_kind_of kind, node
      assert_equal expected.begin, node.location.start_offset, "#{kind} start_offset"
      assert_equal expected.end, node.location.end_offset, "#{kind} end_offset"
    end
  end
end
