# frozen_string_literal: true

module Prism
  class TestCompilePrism < Test::Unit::TestCase
    def test_empty_program
      assert_prism_eval("")
    end

    ############################################################################
    # Literals                                                                 #
    ############################################################################

    def test_FalseNode
      assert_prism_eval("false")
    end

    def test_FloatNode
      assert_prism_eval("1.2")
      assert_prism_eval("1.2e3")
      assert_prism_eval("+1.2e+3")
      assert_prism_eval("-1.2e-3")
    end

    def test_ImaginaryNode
      assert_prism_eval("1i")
      assert_prism_eval("+1.0i")
      assert_prism_eval("1ri")
    end

    def test_IntegerNode
      assert_prism_eval("1")
      assert_prism_eval("+1")
      assert_prism_eval("-1")
      assert_prism_eval("0x10")
      assert_prism_eval("0b10")
      assert_prism_eval("0o10")
      assert_prism_eval("010")
    end

    def test_MatchLastLineNode
      assert_prism_eval("if /foo/; end")
      assert_prism_eval("if /foo/i; end")
      assert_prism_eval("if /foo/x; end")
      assert_prism_eval("if /foo/m; end")
      assert_prism_eval("if /foo/im; end")
      assert_prism_eval("if /foo/mx; end")
      assert_prism_eval("if /foo/xi; end")
      assert_prism_eval("if /foo/ixm; end")
    end

    def test_NilNode
      assert_prism_eval("nil")
    end

    def test_RationalNode
      assert_prism_eval("1.2r")
      assert_prism_eval("+1.2r")
    end

    def test_SelfNode
      assert_prism_eval("self")
    end

    def test_TrueNode
      assert_prism_eval("true")
    end

    ############################################################################
    # Reads                                                                    #
    ############################################################################

    def test_ClassVariableReadNode
      assert_prism_eval("class Prism::TestCompilePrism; @@pit = 1; @@pit; end")
    end

    def test_ConstantPathNode
      assert_prism_eval("Prism::TestCompilePrism")
    end

    def test_ConstantReadNode
      assert_prism_eval("Prism")
    end

    def test_GlobalVariableReadNode
      assert_prism_eval("$pit = 1; $pit")
    end

    def test_InstanceVariableReadNode
      assert_prism_eval("class Prism::TestCompilePrism; @pit = 1; @pit; end")
    end

    def test_LocalVariableReadNode
      assert_prism_eval("pit = 1; pit")
    end

    ############################################################################
    # Writes                                                                   #
    ############################################################################

    def test_ClassVariableTargetNode
      assert_prism_eval("class Prism::TestCompilePrism; @@pit, @@pit1 = 1; end")
    end

    def test_ClassVariableWriteNode
      assert_prism_eval("class Prism::TestCompilePrism; @@pit = 1; end")
    end

    def test_ClassVariableAndWriteNode
      assert_prism_eval("class Prism::TestCompilePrism; @@pit = 0; @@pit &&= 1; end")
    end

    def test_ClassVariableOrWriteNode
      assert_prism_eval("class Prism::TestCompilePrism; @@pit = 1; @@pit ||= 0; end")
      assert_prism_eval("class Prism::TestCompilePrism; @@pit = nil; @@pit ||= 1; end")
    end

    def test_ClassVariableOperatorWriteNode
      assert_prism_eval("class Prism::TestCompilePrism; @@pit = 0; @@pit += 1; end")
    end

    def test_ConstantTargetNode
      # We don't call assert_prism_eval directly in this case becuase we
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

    def test_ConstantWriteNode
      # We don't call assert_prism_eval directly in this case becuase we
      # don't want to assign the constant mutliple times if we run
      # with `--repeat-count`
      # Instead, we eval manually here, and remove the constant to
      constant_name = "YCT"
      source = "#{constant_name} = 1"
      prism_eval = RubyVM::InstructionSequence.compile_prism(source).eval
      assert_equal prism_eval, 1
      Object.send(:remove_const, constant_name)
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

    def test_ConstantPathWriteNode
      assert_prism_eval("Prism::CPWN = 1")
      assert_prism_eval("::CPWN = 1")
    end

    def test_GlobalVariableTargetNode
      assert_prism_eval("$pit, $pit1 = 1")
    end

    def test_GlobalVariableWriteNode
      assert_prism_eval("$pit = 1")
    end

    def test_GlobalVariableAndWriteNode
      assert_prism_eval("$pit = 0; $pit &&= 1")
    end

    def test_GlobalVariableOrWriteNode
      assert_prism_eval("$pit ||= 1")
    end

    def test_GlobalVariableOperatorWriteNode
      assert_prism_eval("$pit = 0; $pit += 1")
    end

    def test_InstanceVariableTargetNode
      assert_prism_eval("class Prism::TestCompilePrism; @pit, @pit1 = 1; end")
    end

    def test_InstanceVariableWriteNode
      assert_prism_eval("class Prism::TestCompilePrism; @pit = 1; end")
    end

    def test_InstanceVariableAndWriteNode
      assert_prism_eval("@pit = 0; @pit &&= 1")
    end

    def test_InstanceVariableOrWriteNode
      assert_prism_eval("@pit ||= 1")
    end

    def test_InstanceVariableOperatorWriteNode
      assert_prism_eval("@pit = 0; @pit += 1")
    end

    def test_LocalVariableTargetNode
      assert_prism_eval("pit, pit1 = 1")
    end

    def test_LocalVariableWriteNode
      assert_prism_eval("pit = 1")
    end

    def test_LocalVariableAndWriteNode
      assert_prism_eval("pit = 0; pit &&= 1")
    end

    def test_LocalVariableOrWriteNode
      assert_prism_eval("pit ||= 1")
    end

    def test_LocalVariableOperatorWriteNode
      assert_prism_eval("pit = 0; pit += 1")
    end

    def test_MatchWriteNode
      assert_prism_eval("/(?<foo>bar)(?<baz>bar>)/ =~ 'barbar'")
      assert_prism_eval("/(?<foo>bar)/ =~ 'barbar'")
    end

    ############################################################################
    # String-likes                                                             #
    ############################################################################

    def test_EmbeddedVariableNode
      # assert_prism_eval('class Prism::TestCompilePrism; @pit = 1; "#@pit"; end')
      # assert_prism_eval('class Prism::TestCompilePrism; @@pit = 1; "#@@pit"; end')
      assert_prism_eval('$pit = 1; "#$pit"')
    end

    def test_InterpolatedMatchLastLineNode
      assert_prism_eval("$pit = '.oo'; if /\#$pit/mix; end")
    end

    def test_InterpolatedRegularExpressionNode
      assert_prism_eval('$pit = 1; /1 #$pit 1/')
      assert_prism_eval('$pit = 1; /#$pit/i')
      assert_prism_eval('/1 #{1 + 2} 1/')
      assert_prism_eval('/1 #{"2"} #{1 + 2} 1/')
    end

    def test_InterpolatedStringNode
      assert_prism_eval('$pit = 1; "1 #$pit 1"')
      assert_prism_eval('"1 #{1 + 2} 1"')
    end

    def test_InterpolatedSymbolNode
      assert_prism_eval('$pit = 1; :"1 #$pit 1"')
      assert_prism_eval(':"1 #{1 + 2} 1"')
    end

    def test_InterpolatedXStringNode
      assert_prism_eval('`echo #{1}`')
      assert_prism_eval('`printf #{"100"}`')
    end

    def test_RegularExpressionNode
      assert_prism_eval('/pit/')
      assert_prism_eval('/pit/i')
      assert_prism_eval('/pit/x')
      assert_prism_eval('/pit/m')
      assert_prism_eval('/pit/im')
      assert_prism_eval('/pit/mx')
      assert_prism_eval('/pit/xi')
      assert_prism_eval('/pit/ixm')
    end

    def test_StringConcatNode
      # assert_prism_eval('"Prism" "::" "TestCompilePrism"')
    end

    def test_StringNode
      assert_prism_eval('"pit"')
    end

    def test_SymbolNode
      assert_prism_eval(":pit")
    end

    def test_XStringNode
      # assert_prism_eval(<<~RUBY)
      #   class Prism::TestCompilePrism
      #     def self.`(command) = command * 2
      #     `pit`
      #   end
      # RUBY
    end

    ############################################################################
    # Structures                                                               #
    ############################################################################

    def test_ArrayNode
      assert_prism_eval("[]")
      assert_prism_eval("[1, 2, 3]")
      assert_prism_eval("%i[foo bar baz]")
      assert_prism_eval("%w[foo bar baz]")
    end

    def test_HashNode
      assert_prism_eval("{}")
      assert_prism_eval("{ a: :a }")
      assert_prism_eval("{ a: :a, b: :b }")
      assert_prism_eval("a = 1; { a: a }")
      assert_prism_eval("a = 1; { a: }")
      assert_prism_eval("{ to_s: }")
      assert_prism_eval("{ Prism: }")
      assert_prism_eval("[ Prism: [:b, :c]]")
    end

    def test_SplatNode
      assert_prism_eval("*b = []")
    end

    ############################################################################
    # Jumps                                                                    #
    ############################################################################

    def test_AndNode
      assert_prism_eval("true && 1")
      assert_prism_eval("false && 1")
    end

    def test_OrNode
      assert_prism_eval("true || 1")
      assert_prism_eval("false || 1")
    end

    def test_IfNode
      assert_prism_eval("if true; 1; end")
      assert_prism_eval("1 if true")
    end

    def test_ElseNode
      assert_prism_eval("if false; 0; else; 1; end")
      assert_prism_eval("if true; 0; else; 1; end")
      assert_prism_eval("true ? 1 : 0")
      assert_prism_eval("false ? 0 : 1")
    end

    def test_FlipFlopNode
      assert_prism_eval("not (1 == 1) .. (2 == 2)")
      assert_prism_eval("not (1 == 1) ... (2 == 2)")
    end

    ############################################################################
    #  Calls / arugments                                                       #
    ############################################################################

    def test_BlockArgumentNode
      assert_prism_eval("1.then(&:to_s)")
    end

    ############################################################################
    # Scopes/statements                                                        #
    ############################################################################

    def test_ClassNode
      assert_prism_eval("class PrismClassA; end")
      assert_prism_eval("class PrismClassA; end; class PrismClassB < PrismClassA; end")
      assert_prism_eval("class PrismClassA; end; class PrismClassA::PrismClassC; end")
      assert_prism_eval(<<-HERE
        class PrismClassA; end
        class PrismClassA::PrismClassC; end
        class PrismClassB; end
        class PrismClassB::PrismClassD < PrismClassA::PrismClassC; end
      HERE
      )
    end

    def test_ModuleNode
      assert_prism_eval("module M; end")
      assert_prism_eval("module M::N; end")
      assert_prism_eval("module ::O; end")
    end

    def test_ParenthesesNode
      assert_prism_eval("()")
      assert_prism_eval("(1)")
    end

    ############################################################################
    # Methods / parameters                                                     #
    ############################################################################

    def test_AliasGlobalVariableNode
      assert_prism_eval("alias $prism_foo $prism_bar")
    end

    def test_AliasMethodNode
      assert_prism_eval("alias :prism_a :to_s")
    end

    def test_UndefNode
      assert_prism_eval("def prism_undef_node_1; end; undef prism_undef_node_1")
      assert_prism_eval(<<-HERE
        def prism_undef_node_2
        end
        def prism_undef_node_3
        end
        undef prism_undef_node_2, prism_undef_node_3
      HERE
      )
      assert_prism_eval(<<-HERE
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
      assert_prism_eval("1 in 1 | 2")
      assert_prism_eval("1 in 2 | 1")
      assert_prism_eval("1 in 2 | 3 | 4 | 1")
      assert_prism_eval("1 in 2 | 3")
    end

    def test_MatchPredicateNode
      assert_prism_eval("1 in 1")
      assert_prism_eval("1.0 in 1.0")
      assert_prism_eval("1i in 1i")
      assert_prism_eval("1r in 1r")

      assert_prism_eval("\"foo\" in \"foo\"")
      assert_prism_eval("\"foo \#{1}\" in \"foo \#{1}\"")

      assert_prism_eval("false in false")
      assert_prism_eval("nil in nil")
      assert_prism_eval("self in self")
      assert_prism_eval("true in true")

      assert_prism_eval("5 in 0..10")
      assert_prism_eval("5 in 0...10")

      assert_prism_eval("[\"5\"] in %w[5]")

      assert_prism_eval("Prism in Prism")
      assert_prism_eval("Prism in ::Prism")

      assert_prism_eval(":prism in :prism")
      assert_prism_eval("%s[prism\#{1}] in %s[prism\#{1}]")
      assert_prism_eval("\"foo\" in /.../")
      assert_prism_eval("\"foo1\" in /...\#{1}/")
      assert_prism_eval("4 in ->(v) { v.even? }")

      assert_prism_eval("5 in foo")

      assert_prism_eval("1 in 2")
    end

    def test_PinnedExpressionNode
      assert_prism_eval("4 in ^(4)")
    end

    def test_PinnedVariableNode
      assert_prism_eval("module Prism; @@prism = 1; 1 in ^@@prism; end")
      assert_prism_eval("module Prism; @prism = 1; 1 in ^@prism; end")
      assert_prism_eval("$prism = 1; 1 in ^$prism")
      assert_prism_eval("prism = 1; 1 in ^prism")
    end

    ############################################################################
    #  Miscellaneous                                                           #
    ############################################################################

    def test_ScopeNode
      assert_separately(%w[], "#{<<-'begin;'}\n#{<<-'end;'}")
      begin;
        def compare_eval(source)
          ruby_eval = RubyVM::InstructionSequence.compile(source).eval
          prism_eval = RubyVM::InstructionSequence.compile_prism(source).eval

          assert_equal ruby_eval, prism_eval
        end

        def assert_prism_eval(source)
          $VERBOSE, verbose_bak = nil, $VERBOSE

          begin
            compare_eval(source)

            # Test "popped" functionality
            compare_eval("#{source}; 1")
          ensure
            $VERBOSE = verbose_bak
          end
        end
        assert_prism_eval("a = 1; tap do; { a: }; end")
        assert_prism_eval("a = 1; def foo(a); a; end")
      end;
    end

    private

    def compare_eval(source)
      ruby_eval = RubyVM::InstructionSequence.compile(source).eval
      prism_eval = RubyVM::InstructionSequence.compile_prism(source).eval

      assert_equal ruby_eval, prism_eval
    end

    def assert_prism_eval(source)
      $VERBOSE, verbose_bak = nil, $VERBOSE

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
