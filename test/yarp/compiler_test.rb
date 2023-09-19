# frozen_string_literal: true

module YARP
  class CompilerTest < Test::Unit::TestCase
    def test_empty_program
      test_yarp_eval("")
    end

    ############################################################################
    # Literals                                                                 #
    ############################################################################

    def test_FalseNode
      test_yarp_eval("false")
    end

    def test_FloatNode
      test_yarp_eval("1.2")
      test_yarp_eval("1.2e3")
      test_yarp_eval("+1.2e+3")
      test_yarp_eval("-1.2e-3")
    end

    def test_ImaginaryNode
      test_yarp_eval("1i")
      test_yarp_eval("+1.0i")
      test_yarp_eval("1ri")
    end

    def test_IntegerNode
      test_yarp_eval("1")
      test_yarp_eval("+1")
      test_yarp_eval("-1")
      test_yarp_eval("0x10")
      test_yarp_eval("0b10")
      test_yarp_eval("0o10")
      test_yarp_eval("010")
    end

    def test_NilNode
      test_yarp_eval("nil")
    end

    def test_RationalNode
      test_yarp_eval("1.2r")
      test_yarp_eval("+1.2r")
    end

    def test_SelfNode
      test_yarp_eval("self")
    end

    def test_TrueNode
      test_yarp_eval("true")
    end

    ############################################################################
    # Reads                                                                    #
    ############################################################################

    def test_ClassVariableReadNode
      test_yarp_eval("class YARP::CompilerTest; @@yct = 1; @@yct; end")
    end

    def test_ConstantPathNode
      test_yarp_eval("YARP::CompilerTest")
    end

    def test_ConstantReadNode
      test_yarp_eval("YARP")
    end

    def test_GlobalVariableReadNode
      test_yarp_eval("$yct = 1; $yct")
    end

    def test_InstanceVariableReadNode
      test_yarp_eval("class YARP::CompilerTest; @yct = 1; @yct; end")
    end

    def test_LocalVariableReadNode
      test_yarp_eval("yct = 1; yct")
    end

    ############################################################################
    # Writes                                                                   #
    ############################################################################

    def test_ClassVariableTargetNode
      test_yarp_eval("class YARP::CompilerTest; @@yct, @@yct1 = 1; end")
    end

    def test_ClassVariableWriteNode
      test_yarp_eval("class YARP::CompilerTest; @@yct = 1; end")
    end

    def test_ClassVariableAndWriteNode
      test_yarp_eval("class YARP::CompilerTest; @@yct = 0; @@yct &&= 1; end")
    end

    def test_ClassVariableOrWriteNode
      test_yarp_eval("class YARP::CompilerTest; @@yct = 1; @@yct ||= 0; end")
      test_yarp_eval("class YARP::CompilerTest; @@yct = nil; @@yct ||= 1; end")
    end

    def test_ClassVariableOperatorWriteNode
      test_yarp_eval("class YARP::CompilerTest; @@yct = 0; @@yct += 1; end")
    end

    def test_ConstantTargetNode
      # We don't call test_yarp_eval directly in this case becuase we
      # don't want to assign the constant mutliple times if we run
      # with `--repeat-count`
      # Instead, we eval manually here, and remove the constant to
      constant_names = ["YCT", "YCT2"]
      source = "#{constant_names.join(",")} = 1"
      yarp_eval = RubyVM::InstructionSequence.compile_yarp(source).eval
      assert_equal yarp_eval, 1
      constant_names.map { |name|
        Object.send(:remove_const, name)
      }
    end

    def test_ConstantWriteNode
      # We don't call test_yarp_eval directly in this case becuase we
      # don't want to assign the constant mutliple times if we run
      # with `--repeat-count`
      # Instead, we eval manually here, and remove the constant to
      constant_name = "YCT"
      source = "#{constant_name} = 1"
      yarp_eval = RubyVM::InstructionSequence.compile_yarp(source).eval
      assert_equal yarp_eval, 1
      Object.send(:remove_const, constant_name)
    end

    def test_ConstantPathWriteNode
      # test_yarp_eval("YARP::YCT = 1")
    end

    def test_GlobalVariableTargetNode
      test_yarp_eval("$yct, $yct1 = 1")
    end

    def test_GlobalVariableWriteNode
      test_yarp_eval("$yct = 1")
    end

    def test_GlobalVariableAndWriteNode
      test_yarp_eval("$yct = 0; $yct &&= 1")
    end

    def test_GlobalVariableOrWriteNode
      test_yarp_eval("$yct ||= 1")
    end

    def test_GlobalVariableOperatorWriteNode
      test_yarp_eval("$yct = 0; $yct += 1")
    end

    def test_InstanceVariableTargetNode
      test_yarp_eval("class YARP::CompilerTest; @yct, @yct1 = 1; end")
    end

    def test_InstanceVariableWriteNode
      test_yarp_eval("class YARP::CompilerTest; @yct = 1; end")
    end

    def test_InstanceVariableAndWriteNode
      test_yarp_eval("@yct = 0; @yct &&= 1")
    end

    def test_InstanceVariableOrWriteNode
      test_yarp_eval("@yct ||= 1")
    end

    def test_InstanceVariableOperatorWriteNode
      test_yarp_eval("@yct = 0; @yct += 1")
    end

    def test_LocalVariableTargetNode
      test_yarp_eval("yct, yct1 = 1")
    end

    def test_LocalVariableWriteNode
      test_yarp_eval("yct = 1")
    end

    def test_LocalVariableAndWriteNode
      test_yarp_eval("yct = 0; yct &&= 1")
    end

    def test_LocalVariableOrWriteNode
      test_yarp_eval("yct ||= 1")
    end

    def test_LocalVariableOperatorWriteNode
      test_yarp_eval("yct = 0; yct += 1")
    end

    ############################################################################
    # String-likes                                                             #
    ############################################################################

    def test_EmbeddedVariableNode
      # test_yarp_eval('class YARP::CompilerTest; @yct = 1; "#@yct"; end')
      # test_yarp_eval('class YARP::CompilerTest; @@yct = 1; "#@@yct"; end')
      test_yarp_eval('$yct = 1; "#$yct"')
    end

    def test_InterpolatedRegularExpressionNode
      test_yarp_eval('$yct = 1; /1 #$yct 1/')
      test_yarp_eval('/1 #{1 + 2} 1/')
      test_yarp_eval('/1 #{"2"} #{1 + 2} 1/')
    end

    def test_InterpolatedStringNode
      test_yarp_eval('$yct = 1; "1 #$yct 1"')
      test_yarp_eval('"1 #{1 + 2} 1"')
    end

    def test_InterpolatedSymbolNode
      test_yarp_eval('$yct = 1; :"1 #$yct 1"')
      test_yarp_eval(':"1 #{1 + 2} 1"')
    end

    def test_InterpolatedXStringNode
      test_yarp_eval('`echo #{1}`')
      test_yarp_eval('`printf "100"`')
    end

    def test_RegularExpressionNode
      test_yarp_eval('/yct/')
    end

    def test_StringConcatNode
      # test_yarp_eval('"YARP" "::" "CompilerTest"')
    end

    def test_StringNode
      test_yarp_eval('"yct"')
    end

    def test_SymbolNode
      test_yarp_eval(":yct")
    end

    def test_XStringNode
      # test_yarp_eval(<<~RUBY)
      #   class YARP::CompilerTest
      #     def self.`(command) = command * 2
      #     `yct`
      #   end
      # RUBY
    end

    ############################################################################
    # Jumps                                                                    #
    ############################################################################

    def test_AndNode
      test_yarp_eval("true && 1")
      test_yarp_eval("false && 1")
    end

    def test_OrNode
      test_yarp_eval("true || 1")
      test_yarp_eval("false || 1")
    end

    ############################################################################
    # Scopes/statements                                                        #
    ############################################################################

    def test_ParenthesesNode
      test_yarp_eval("()")
      test_yarp_eval("(1)")
    end

    private

    def test_yarp_eval(source)
      ruby_eval = RubyVM::InstructionSequence.compile(source).eval
      yarp_eval = RubyVM::InstructionSequence.compile_yarp(source).eval

      assert_equal ruby_eval, yarp_eval
    end
  end
end
