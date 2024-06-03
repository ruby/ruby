# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class SourceLocationTest < TestCase
    def test_AliasGlobalVariableNode
      assert_location(AliasGlobalVariableNode, "alias $foo $bar")
    end

    def test_AliasMethodNode
      assert_location(AliasMethodNode, "alias foo bar")
    end

    def test_AlternationPatternNode
      assert_location(AlternationPatternNode, "foo => bar | baz", 7...16, &:pattern)
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
      assert_location(ElseNode, "if foo; bar; else; baz; end", 13...27, &:consequent)
      assert_location(ElseNode, "foo ? bar : baz", 10...15, &:consequent)
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

    def test_InterpolatedXStringNode
      assert_location(InterpolatedXStringNode, '`foo #{bar} baz`')
    end

    def test_ItLocalVariableReadNode
      assert_location(ItLocalVariableReadNode, "-> { it }", 5...7) do |node|
        node.body.body.first
      end

      assert_location(ItLocalVariableReadNode, "foo { it }", 6...8) do |node|
        node.block.body.body.first
      end

      assert_location(CallNode, "-> { it }", 5...7, version: "3.3.0") do |node|
        node.body.body.first
      end

      assert_location(ItLocalVariableReadNode, "-> { it }", 5...7, version: "3.4.0") do |node|
        node.body.body.first
      end
    end

    def test_ItParametersNode
      assert_location(ItParametersNode, "-> { it }", &:parameters)
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

    def test_OrNode
      assert_location(OrNode, "foo || bar")
      assert_location(OrNode, "foo or bar")
    end

    def test_ParametersNode
      assert_location(ParametersNode, "def foo(bar, baz); end", 8...16, &:parameters)
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

    def test_PinnedVariableNode
      assert_location(PinnedVariableNode, "bar = 1; foo in ^bar", 16...20, &:pattern)
      assert_location(PinnedVariableNode, "proc { 1 in ^it }.call(1)", 12...15) do |node|
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
      assert_location(RescueNode, code, 30...50) { |node| node.rescue_clause.consequent }
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
    end

    def test_StatementsNode
      assert_location(StatementsNode, "foo { 1 }", 6...7) { |node| node.block.body }

      assert_location(StatementsNode, "(1)", 1...2, &:body)

      assert_location(StatementsNode, "def foo; 1; end", 9...10, &:body)
      assert_location(StatementsNode, "def foo = 1", 10...11, &:body)
      assert_location(StatementsNode, "def foo; 1\n2; end", 9...12, &:body)

      assert_location(StatementsNode, "if foo; bar; end", 8...11, &:statements)
      assert_location(StatementsNode, "foo if bar", 0...3, &:statements)

      assert_location(StatementsNode, "if foo; foo; elsif bar; bar; end", 24...27) { |node| node.consequent.statements }
      assert_location(StatementsNode, "if foo; foo; else; bar; end", 19...22) { |node| node.consequent.statements }

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
      expected = Prism.constants.grep(/.Node$/).sort - %i[MissingNode ProgramNode]
      actual = SourceLocationTest.instance_methods(false).grep(/.Node$/).map { |name| name[5..].to_sym }.sort
      assert_equal expected, actual
    end

    private

    def assert_location(kind, source, expected = 0...source.length, **options)
      result = Prism.parse(source, **options)
      assert result.success?

      node = result.value.statements.body.last
      node = yield node if block_given?

      if expected.begin == 0
        assert_equal 0, node.location.start_column
      end

      if expected.end == source.length
        assert_equal source.split("\n").last.length, node.location.end_column
      end

      assert_kind_of kind, node
      assert_equal expected.begin, node.location.start_offset
      assert_equal expected.end, node.location.end_offset
    end
  end
end
