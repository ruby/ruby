# frozen_string_literal: true

module Prism
  class ISeqTest < Test::Unit::TestCase
    def test_empty_program
      test_prism_eval("")
    end

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

    def test_TrueNode
      test_prism_eval("true")
    end

    ############################################################################
    # Reads                                                                    #
    ############################################################################

    def test_ClassVariableReadNode
      test_prism_eval("class Prism::ISeqTest; @@pit = 1; @@pit; end")
    end

    def test_ConstantPathNode
      test_prism_eval("Prism::ISeqTest")
    end

    def test_ConstantReadNode
      test_prism_eval("Prism")
    end

    def test_GlobalVariableReadNode
      test_prism_eval("$pit = 1; $pit")
    end

    def test_InstanceVariableReadNode
      test_prism_eval("class Prism::ISeqTest; @pit = 1; @pit; end")
    end

    def test_LocalVariableReadNode
      test_prism_eval("pit = 1; pit")
    end

    ############################################################################
    # Writes                                                                   #
    ############################################################################

    def test_ClassVariableTargetNode
      test_prism_eval("class Prism::ISeqTest; @@pit, @@pit1 = 1; end")
    end

    def test_ClassVariableWriteNode
      test_prism_eval("class Prism::ISeqTest; @@pit = 1; end")
    end

    def test_ClassVariableAndWriteNode
      test_prism_eval("class Prism::ISeqTest; @@pit = 0; @@pit &&= 1; end")
    end

    def test_ClassVariableOrWriteNode
      test_prism_eval("class Prism::ISeqTest; @@pit = 1; @@pit ||= 0; end")
      test_prism_eval("class Prism::ISeqTest; @@pit = nil; @@pit ||= 1; end")
    end

    def test_ClassVariableOperatorWriteNode
      test_prism_eval("class Prism::ISeqTest; @@pit = 0; @@pit += 1; end")
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
      # test_prism_eval("Prism::YCT = 1")
    end

    def test_GlobalVariableTargetNode
      test_prism_eval("$pit, $pit1 = 1")
    end

    def test_GlobalVariableWriteNode
      test_prism_eval("$pit = 1")
    end

    def test_GlobalVariableAndWriteNode
      test_prism_eval("$pit = 0; $pit &&= 1")
    end

    def test_GlobalVariableOrWriteNode
      test_prism_eval("$pit ||= 1")
    end

    def test_GlobalVariableOperatorWriteNode
      test_prism_eval("$pit = 0; $pit += 1")
    end

    def test_InstanceVariableTargetNode
      test_prism_eval("class Prism::ISeqTest; @pit, @pit1 = 1; end")
    end

    def test_InstanceVariableWriteNode
      test_prism_eval("class Prism::ISeqTest; @pit = 1; end")
    end

    def test_InstanceVariableAndWriteNode
      test_prism_eval("@pit = 0; @pit &&= 1")
    end

    def test_InstanceVariableOrWriteNode
      test_prism_eval("@pit ||= 1")
    end

    def test_InstanceVariableOperatorWriteNode
      test_prism_eval("@pit = 0; @pit += 1")
    end

    def test_LocalVariableTargetNode
      test_prism_eval("pit, pit1 = 1")
    end

    def test_LocalVariableWriteNode
      test_prism_eval("pit = 1")
    end

    def test_LocalVariableAndWriteNode
      test_prism_eval("pit = 0; pit &&= 1")
    end

    def test_LocalVariableOrWriteNode
      test_prism_eval("pit ||= 1")
    end

    def test_LocalVariableOperatorWriteNode
      test_prism_eval("pit = 0; pit += 1")
    end

    ############################################################################
    # String-likes                                                             #
    ############################################################################

    def test_EmbeddedVariableNode
      # test_prism_eval('class Prism::ISeqTest; @pit = 1; "#@pit"; end')
      # test_prism_eval('class Prism::ISeqTest; @@pit = 1; "#@@pit"; end')
      test_prism_eval('$pit = 1; "#$pit"')
    end

    def test_InterpolatedRegularExpressionNode
      test_prism_eval('$pit = 1; /1 #$pit 1/')
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
      # test_prism_eval('"Prism" "::" "ISeqTest"')
    end

    def test_StringNode
      test_prism_eval('"pit"')
    end

    def test_SymbolNode
      test_prism_eval(":pit")
    end

    def test_XStringNode
      # test_prism_eval(<<~RUBY)
      #   class Prism::ISeqTest
      #     def self.`(command) = command * 2
      #     `pit`
      #   end
      # RUBY
    end

    ############################################################################
    # Jumps                                                                    #
    ############################################################################

    def test_AndNode
      test_prism_eval("true && 1")
      test_prism_eval("false && 1")
    end

    def test_OrNode
      test_prism_eval("true || 1")
      test_prism_eval("false || 1")
    end

    ############################################################################
    #  Calls / arugments                                                       #
    ############################################################################

    def test_BlockArgumentNode
      test_prism_eval("1.then(&:to_s)")
    end

    ############################################################################
    # Scopes/statements                                                        #
    ############################################################################

    def test_ParenthesesNode
      test_prism_eval("()")
      test_prism_eval("(1)")
    end

    private

    def compare_eval(source)
      ruby_eval = RubyVM::InstructionSequence.compile(source).eval
      prism_eval = RubyVM::InstructionSequence.compile_prism(source).eval

      assert_equal ruby_eval, prism_eval
    end

    def test_prism_eval(source)
      compare_eval(source)

      begin
        $VERBOSE, verbose_bak = nil, $VERBOSE
        # Test "popped" functionality
        compare_eval("#{source}; 1")
      ensure
        $VERBOSE = verbose_bak
      end
    end
  end
end
