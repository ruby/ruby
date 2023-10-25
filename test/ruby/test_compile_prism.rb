# frozen_string_literal: true

# This file is organized to match itemization in https://github.com/ruby/prism/issues/1335
module Prism
  class TestCompilePrism < Test::Unit::TestCase
    ############################################################################
    # Literals                                                                 #
    ############################################################################

    def test_FalseNode
      test_prism_eval("false")
    end

    def test_FloatNode
      test_prism_eval("1.2")
      test_prism_eval("1.2e3")
      test_prism_eval("+1.2e+3")
      test_prism_eval("-1.2e-3")
    end

    def test_ImaginaryNode
      test_prism_eval("1i")
      test_prism_eval("+1.0i")
      test_prism_eval("1ri")
    end

    def test_IntegerNode
      test_prism_eval("1")
      test_prism_eval("+1")
      test_prism_eval("-1")
      test_prism_eval("0x10")
      test_prism_eval("0b10")
      test_prism_eval("0o10")
      test_prism_eval("010")
    end

    def test_NilNode
      test_prism_eval("nil")
    end

    def test_RationalNode
      test_prism_eval("1.2r")
      test_prism_eval("+1.2r")
    end

    def test_SelfNode
      test_prism_eval("self")
    end

    def test_SourceEncodingNode
      test_prism_eval("__ENCODING__")
    end

    def test_SourceFileNode
      test_prism_eval("__FILE__")
    end

    def test_SourceLineNode
      ruby_eval = RubyVM::InstructionSequence.compile("__LINE__").eval
      prism_eval = RubyVM::InstructionSequence.compile_prism("__LINE__").eval

      assert_equal ruby_eval, prism_eval
    end

    def test_TrueNode
      test_prism_eval("true")
    end

    ############################################################################
    # Reads                                                                    #
    ############################################################################

    def test_BackReferenceReadNode
      test_prism_eval("$+")
    end

    def test_ClassVariableReadNode
      test_prism_eval("class Prism::TestCompilePrism; @@pit = 1; @@pit; end")
    end

    def test_ConstantPathNode
      test_prism_eval("Prism::TestCompilePrism")
    end

    def test_ConstantReadNode
      test_prism_eval("Prism")
    end

    def test_DefinedNode
      # TODO:
      # test_prism_eval("defined? foo")
    end

    def test_GlobalVariableReadNode
      test_prism_eval("$pit = 1; $pit")
    end

    def test_InstanceVariableReadNode
      test_prism_eval("class Prism::TestCompilePrism; @pit = 1; @pit; end")
    end

    def test_LocalVariableReadNode
      test_prism_eval("pit = 1; pit")
    end

    def test_NumberedReferenceReadNode
      test_prism_eval("$1")
      test_prism_eval("$99999")
    end

    ############################################################################
    # Writes                                                                   #
    ############################################################################

    def test_ClassVariableAndWriteNode
      test_prism_eval("class Prism::TestCompilePrism; @@pit = 0; @@pit &&= 1; end")
    end

    def test_ClassVariableOperatorWriteNode
      test_prism_eval("class Prism::TestCompilePrism; @@pit = 0; @@pit += 1; end")
    end

    def test_ClassVariableOrWriteNode
      test_prism_eval("class Prism::TestCompilePrism; @@pit = 1; @@pit ||= 0; end")
      test_prism_eval("class Prism::TestCompilePrism; @@pit = nil; @@pit ||= 1; end")
    end

    def test_ClassVariableWriteNode
      test_prism_eval("class Prism::TestCompilePrism; @@pit = 1; end")
    end

    def test_ConstantAndWriteNode
      test_prism_eval("Constant = 1; Constant &&= 1")
    end

    def test_ConstantOperatorWriteNode
      test_prism_eval("Constant = 1; Constant += 1")
    end

    def test_ConstantOrWriteNode
      test_prism_eval("Constant = 1; Constant ||= 1")
    end

    def test_ConstantWriteNode
      # We don't call test_prism_eval directly in this case becuase we
      # don't want to assign the constant mutliple times if we run
      # with `--repeat-count`
      # Instead, we eval manually here, and remove the constant to
      constant_name = "YCT"
      source = "#{constant_name} = 1"
      prism_eval = RubyVM::InstructionSequence.compile_prism(source).eval
      assert_equal prism_eval, 1
      Object.send(:remove_const, constant_name)
    end

    def test_ConstantPathWriteNode
      test_prism_eval("Prism::CPWN = 1")
      test_prism_eval("::CPWN = 1")
    end

    def test_GlobalVariableAndWriteNode
      test_prism_eval("$pit = 0; $pit &&= 1")
    end

    def test_GlobalVariableOperatorWriteNode
      test_prism_eval("$pit = 0; $pit += 1")
    end

    def test_GlobalVariableOrWriteNode
      test_prism_eval("$pit ||= 1")
    end

    def test_GlobalVariableWriteNode
      test_prism_eval("$pit = 1")
    end

    def test_InstanceVariableAndWriteNode
      test_prism_eval("@pit = 0; @pit &&= 1")
    end

    def test_InstanceVariableOperatorWriteNode
      test_prism_eval("@pit = 0; @pit += 1")
    end

    def test_InstanceVariableOrWriteNode
      test_prism_eval("@pit ||= 1")
    end

    def test_InstanceVariableWriteNode
      test_prism_eval("class Prism::TestCompilePrism; @pit = 1; end")
    end

    def test_LocalVariableAndWriteNode
      test_prism_eval("pit = 0; pit &&= 1")
    end

    def test_LocalVariableOperatorWriteNode
      test_prism_eval("pit = 0; pit += 1")
    end

    def test_LocalVariableOrWriteNode
      test_prism_eval("pit ||= 1")
    end

    def test_LocalVariableWriteNode
      test_prism_eval("pit = 1")
    end

    def test_MatchWriteNode
      test_prism_eval("/(?<foo>bar)(?<baz>bar>)/ =~ 'barbar'")
      test_prism_eval("/(?<foo>bar)/ =~ 'barbar'")
    end

    ############################################################################
    # Multi-writes                                                             #
    ############################################################################

    def test_ClassVariableTargetNode
      test_prism_eval("class Prism::TestCompilePrism; @@pit, @@pit1 = 1; end")
    end

    def test_ConstantTargetNode
      # We don't call test_prism_eval directly in this case becuase we
      # don't want to assign the constant mutliple times if we run
      # with `--repeat-count`
      # Instead, we eval manually here, and remove the constant to
      constant_names = ["YCT", "YCT2"]
      source = "#{constant_names.join(",")} = 1"
      prism_eval = RubyVM::InstructionSequence.compile_prism(source).eval
      assert_equal prism_eval, 1
      constant_names.map { |name|
        Object.send(:remove_const, name)
      }
    end

    def test_ConstantPathTargetNode
      verbose = $VERBOSE
      # Create some temporary nested constants
      Object.send(:const_set, "MyFoo", Object)
      Object.const_get("MyFoo").send(:const_set, "Bar", Object)

      constant_names = ["MyBar", "MyFoo::Bar", "MyFoo::Bar::Baz"]
      source = "#{constant_names.join(",")} = Object"
      iseq = RubyVM::InstructionSequence.compile_prism(source)
      $VERBOSE = nil
      prism_eval = iseq.eval
      $VERBOSE = verbose
      assert_equal prism_eval, Object
    ensure
      ## Teardown temp constants
      Object.const_get("MyFoo").send(:remove_const, "Bar")
      Object.send(:remove_const, "MyFoo")
      Object.send(:remove_const, "MyBar")
      $VERBOSE = verbose
    end

    def test_GlobalVariableTargetNode
      test_prism_eval("$pit, $pit1 = 1")
    end

    def test_InstanceVariableTargetNode
      test_prism_eval("class Prism::TestCompilePrism; @pit, @pit1 = 1; end")
    end

    def test_LocalVariableTargetNode
      test_prism_eval("pit, pit1 = 1")
    end

    def test_MultiWriteNode
      test_prism_eval("foo, bar = [1,2]")
    end

    ############################################################################
    # String-likes                                                             #
    ############################################################################

    def test_EmbeddedStatementsNode
      test_prism_eval('"foo #{to_s} baz"')
    end

    def test_EmbeddedVariableNode
      test_prism_eval('class Prism::TestCompilePrism; @pit = 1; "#@pit"; end')
      test_prism_eval('class Prism::TestCompilePrism; @@pit = 1; "#@@pit"; end')
      test_prism_eval('$pit = 1; "#$pit"')
    end

    def test_InterpolatedMatchLastLineNode
      test_prism_eval("$pit = '.oo'; if /\#$pit/mix; end")
    end

    def test_InterpolatedRegularExpressionNode
      test_prism_eval('$pit = 1; /1 #$pit 1/')
      test_prism_eval('$pit = 1; /#$pit/i')
      test_prism_eval('/1 #{1 + 2} 1/')
      test_prism_eval('/1 #{"2"} #{1 + 2} 1/')
    end

    def test_InterpolatedStringNode
      test_prism_eval('$pit = 1; "1 #$pit 1"')
      test_prism_eval('"1 #{1 + 2} 1"')
    end

    def test_InterpolatedSymbolNode
      test_prism_eval('$pit = 1; :"1 #$pit 1"')
      test_prism_eval(':"1 #{1 + 2} 1"')
    end

    def test_InterpolatedXStringNode
      test_prism_eval('`echo #{1}`')
      test_prism_eval('`printf #{"100"}`')
    end

    def test_MatchLastLineNode
      test_prism_eval("if /foo/; end")
      test_prism_eval("if /foo/i; end")
      test_prism_eval("if /foo/x; end")
      test_prism_eval("if /foo/m; end")
      test_prism_eval("if /foo/im; end")
      test_prism_eval("if /foo/mx; end")
      test_prism_eval("if /foo/xi; end")
      test_prism_eval("if /foo/ixm; end")
    end

    def test_RegularExpressionNode
      test_prism_eval('/pit/')
      test_prism_eval('/pit/i')
      test_prism_eval('/pit/x')
      test_prism_eval('/pit/m')
      test_prism_eval('/pit/im')
      test_prism_eval('/pit/mx')
      test_prism_eval('/pit/xi')
      test_prism_eval('/pit/ixm')
    end

    def test_StringConcatNode
      test_prism_eval('"Prism" "::" "TestCompilePrism"')
    end

    def test_StringNode
      test_prism_eval('"pit"')
    end

    def test_SymbolNode
      test_prism_eval(":pit")
    end

    def test_XStringNode
      test_prism_eval(<<~RUBY)
        class Prism::TestCompilePrism
          def self.`(command) = command * 2
          `pit`
        end
      RUBY
    end

    ############################################################################
    # Structures                                                               #
    ############################################################################

    def test_ArrayNode
      test_prism_eval("[]")
      test_prism_eval("[1, 2, 3]")
      test_prism_eval("%i[foo bar baz]")
      test_prism_eval("%w[foo bar baz]")
    end

    def test_AssocNode
      test_prism_eval("{ foo: :bar }")
    end

    def test_AssocSplatNode
      test_prism_eval("foo = { a: 1 }; { **foo }")
      test_prism_eval("foo = { a: 1 }; bar = foo; { **foo, b: 2, **bar, c: 3 }")
      test_prism_eval("foo = { a: 1 }; { b: 2, **foo, c: 3}")
    end

    def test_HashNode
      test_prism_eval("{}")
      test_prism_eval("{ a: :a }")
      test_prism_eval("{ a: :a, b: :b }")
      test_prism_eval("a = 1; { a: a }")
      test_prism_eval("a = 1; { a: }")
      test_prism_eval("{ to_s: }")
      test_prism_eval("{ Prism: }")
      test_prism_eval("[ Prism: [:b, :c]]")
    end

    def test_ImplicitNode
      test_prism_eval("{ to_s: }")
    end

    def test_RangeNode
      test_prism_eval("1..2")
      test_prism_eval("1...2")
      test_prism_eval("..2")
      test_prism_eval("...2")
      test_prism_eval("1..")
      test_prism_eval("1...")
    end

    def test_SplatNode
      test_prism_eval("*b = []")
    end

    ############################################################################
    # Jumps                                                                    #
    ############################################################################

    def test_AndNode
      test_prism_eval("true && 1")
      test_prism_eval("false && 1")
    end

    def test_ElseNode
      test_prism_eval("if false; 0; else; 1; end")
      test_prism_eval("if true; 0; else; 1; end")
      test_prism_eval("true ? 1 : 0")
      test_prism_eval("false ? 0 : 1")
    end

    def test_FlipFlopNode
      test_prism_eval("not (1 == 1) .. (2 == 2)")
      test_prism_eval("not (1 == 1) ... (2 == 2)")
    end

    def test_IfNode
      test_prism_eval("if true; 1; end")
      test_prism_eval("1 if true")
      test_prism_eval('a = b = 1; if a..b; end')
      test_prism_eval('if "a".."b"; end')
      test_prism_eval('if "a"..; end')
      test_prism_eval('if .."b"; end')
      test_prism_eval('if ..1; end')
      test_prism_eval('if 1..; end')
      test_prism_eval('if 1..2; end')
    end

    def test_OrNode
      test_prism_eval("true || 1")
      test_prism_eval("false || 1")
    end

    def test_UnlessNode
      test_prism_eval("1 unless true")
      test_prism_eval("1 unless false")
      test_prism_eval("unless true; 1; end")
      test_prism_eval("unless false; 1; end")
    end

    def test_UntilNode
      test_prism_eval("a = 0; until a == 1; a = a + 1; end")
    end

    def test_WhileNode
      test_prism_eval("a = 0; while a != 1; a = a + 1; end")
    end

    ############################################################################
    #  Throws                                                                  #
    ############################################################################

    def test_BeginNode
      test_prism_eval("begin; 1; end")
    end

    def test_BreakNode
      test_prism_eval("while true; break; end")
      test_prism_eval("while true; break 1; end")
    end

    def test_NextNode
      # TODO:
      # test_prism_eval("2.times do |i|; next if i == 1; end")
    end

    def test_RedoNode
      # TODO:
      # test_prism_eval(<<-CODE
      # counter = 0

      # 5.times do |i|
      #   counter += 1
      #   if i == 2 && counter < 3
      #     redo
      #   end
      # end
      # CODE
      # )
    end

    def test_ReturnNode
      test_prism_eval("def return_node; return 1; end")
    end

    ############################################################################
    # Scopes/statements                                                        #
    ############################################################################

    def test_BlockNode
      test_prism_eval("[1, 2, 3].each { |num| num }")

      test_prism_eval("[].tap { _1 }")
    end

    def test_ClassNode
      test_prism_eval("class PrismClassA; end")
      test_prism_eval("class PrismClassA; end; class PrismClassB < PrismClassA; end")
      test_prism_eval("class PrismClassA; end; class PrismClassA::PrismClassC; end")
      test_prism_eval(<<-HERE
        class PrismClassA; end
        class PrismClassA::PrismClassC; end
        class PrismClassB; end
        class PrismClassB::PrismClassD < PrismClassA::PrismClassC; end
      HERE
      )
    end

    def test_DefNode
      test_prism_eval("def prism_method; end")
      test_prism_eval("a = Object.new; def a.prism_singleton; :ok; end; a.prism_singleton")
    end

    def test_LambdaNode
      test_prism_eval("-> { to_s }.call")
    end

    def test_ModuleNode
      test_prism_eval("module M; end")
      test_prism_eval("module M::N; end")
      test_prism_eval("module ::O; end")
    end

    def test_ParenthesesNode
      test_prism_eval("()")
      test_prism_eval("(1)")
    end

    def test_PreExecutionNode
      # BEGIN {} must be defined at the top level, so we need to manually
      # call the evals here instead of calling `test_prism_eval`
      ruby_eval = RubyVM::InstructionSequence.compile("BEGIN { a = 1 }; 2").eval
      prism_eval = RubyVM::InstructionSequence.compile_prism("BEGIN { a = 1 }; 2").eval
      assert_equal ruby_eval, prism_eval

      ruby_eval = RubyVM::InstructionSequence.compile("b = 2; BEGIN { a = 1 }; a + b").eval
      prism_eval = RubyVM::InstructionSequence.compile_prism("b = 2; BEGIN { a = 1 }; a + b").eval
      assert_equal ruby_eval, prism_eval
    end

    def test_ProgramNode
      test_prism_eval("")
      test_prism_eval("1")
    end

    def test_SingletonClassNode
      test_prism_eval("class << self; end")
    end

    def test_StatementsNode
      test_prism_eval("1")
    end

    def test_YieldNode
      test_prism_eval("def prism_test_yield_node; yield; end")
    end

    ############################################################################
    #  Calls / arugments                                                       #
    ############################################################################

    def test_ArgumentsNode
      test_prism_eval("[].push 1")
    end

    def test_BlockArgumentNode
      test_prism_eval("1.then(&:to_s)")
    end

    def test_BlockLocalVariableNode
      test_prism_eval(<<-CODE
        pm_var = "outer scope variable"

        1.times { |;pm_var| pm_var = "inner scope variable"; pm_var }
      CODE
      )

      test_prism_eval(<<-CODE
        pm_var = "outer scope variable"

        1.times { |;pm_var| pm_var = "inner scope variable"; pm_var }
        pm_var
      CODE
      )
    end

    def test_CallNode
      test_prism_eval("to_s")
    end

    def test_KeywordHashNode
      test_prism_eval("[a: [:b, :c]]")
    end

    ############################################################################
    # Methods / parameters                                                     #
    ############################################################################

    def test_AliasGlobalVariableNode
      test_prism_eval("alias $prism_foo $prism_bar")
    end

    def test_AliasMethodNode
      test_prism_eval("alias :prism_a :to_s")
    end

    def test_BlockParametersNode
      test_prism_eval("Object.tap { || }")
      test_prism_eval("[1].map { |num| num }")
      test_prism_eval("[1].map { |a; b| b = 2; a + b}")
    end

    def test_OptionalParameterNode
      test_prism_eval("def prism_test_optional_param_node(bar = nil); end")
    end

    def test_UndefNode
      test_prism_eval("def prism_undef_node_1; end; undef prism_undef_node_1")
      test_prism_eval(<<-HERE
        def prism_undef_node_2
        end
        def prism_undef_node_3
        end
        undef prism_undef_node_2, prism_undef_node_3
      HERE
      )
      test_prism_eval(<<-HERE
        def prism_undef_node_4
        end
        undef :'prism_undef_node_#{4}'
      HERE
      )
    end

    ############################################################################
    # Pattern matching                                                         #
    ############################################################################

    def test_AlternationPatternNode
      test_prism_eval("1 in 1 | 2")
      test_prism_eval("1 in 2 | 1")
      test_prism_eval("1 in 2 | 3 | 4 | 1")
      test_prism_eval("1 in 2 | 3")
    end

    def test_MatchPredicateNode
      test_prism_eval("1 in 1")
      test_prism_eval("1.0 in 1.0")
      test_prism_eval("1i in 1i")
      test_prism_eval("1r in 1r")

      test_prism_eval("\"foo\" in \"foo\"")
      test_prism_eval("\"foo \#{1}\" in \"foo \#{1}\"")

      test_prism_eval("false in false")
      test_prism_eval("nil in nil")
      test_prism_eval("self in self")
      test_prism_eval("true in true")

      test_prism_eval("5 in 0..10")
      test_prism_eval("5 in 0...10")

      test_prism_eval("[\"5\"] in %w[5]")

      test_prism_eval("Prism in Prism")
      test_prism_eval("Prism in ::Prism")

      test_prism_eval(":prism in :prism")
      test_prism_eval("%s[prism\#{1}] in %s[prism\#{1}]")
      test_prism_eval("\"foo\" in /.../")
      test_prism_eval("\"foo1\" in /...\#{1}/")
      test_prism_eval("4 in ->(v) { v.even? }")

      test_prism_eval("5 in foo")

      test_prism_eval("1 in 2")
    end

    def test_PinnedExpressionNode
      test_prism_eval("4 in ^(4)")
    end

    def test_PinnedVariableNode
      test_prism_eval("module Prism; @@prism = 1; 1 in ^@@prism; end")
      test_prism_eval("module Prism; @prism = 1; 1 in ^@prism; end")
      test_prism_eval("$prism = 1; 1 in ^$prism")
      test_prism_eval("prism = 1; 1 in ^prism")
    end

    ############################################################################
    #  Miscellaneous                                                           #
    ############################################################################

    def test_ScopeNode
      assert_separately(%w[], "#{<<-'begin;'}\n#{<<-'end;'}")
                        begin;
    def compare_eval(source)
      ruby_eval = RubyVM::InstructionSequence.compile("module A; " + source + "; end").eval
      prism_eval = RubyVM::InstructionSequence.compile_prism("module B; " + source + "; end").eval

      assert_equal ruby_eval, prism_eval
    end

    def test_prism_eval(source)
      $VERBOSE, verbose_bak = nil, $VERBOSE

      begin
        compare_eval(source)

        # Test "popped" functionality
        compare_eval("#{source}; 1")
      ensure
        $VERBOSE = verbose_bak
      end
    end
      test_prism_eval("a = 1; 1.times do; { a: }; end")
      test_prism_eval("a = 1; def foo(a); a; end")
                        end;
    end

    ############################################################################
    # Errors                                                                   #
    ############################################################################

    def test_MissingNode
      # TODO
    end

    ############################################################################
    #  Encoding                                                                #
    ############################################################################

    def test_encoding
      test_prism_eval('"però"')
      test_prism_eval(":però")
    end

    private

    def compare_eval(source)
      ruby_eval = RubyVM::InstructionSequence.compile(source).eval
      prism_eval = RubyVM::InstructionSequence.compile_prism(source).eval

      assert_equal ruby_eval, prism_eval
    end

    def test_prism_eval(source)
      $VERBOSE, verbose_bak = nil, $VERBOSE

      source = "class Prism::TestCompilePrism\n#{source}\nend"
      begin
        compare_eval(source)

        # Test "popped" functionality
        compare_eval("#{source}; 1")
      ensure
        $VERBOSE = verbose_bak
      end
    end
  end
end
