# frozen_string_literal: true

module YARP
  class CompilerTest < Test::Unit::TestCase
    ############################################################################
    # Literals                                                                 #
    ############################################################################

    def test_FalseNode
      assert_equal false, compile("false")
    end

    def test_FloatNode
      assert_equal 1.0, compile("1.0")
      assert_equal 1.0e0, compile("1.0e0")
      assert_equal(+1.0e+0, compile("+1.0e+0"))
      assert_equal(-1.0e-0, compile("-1.0e-0"))
    end

    def test_ImaginaryNode
      # assert_equal 1i, compile("1i")
      # assert_equal +1.0i, compile("+1.0i")
      # assert_equal 1ri, compile("1ri")
    end

    def test_IntegerNode
      assert_equal 1, compile("1")
      assert_equal(+1, compile("+1"))
      assert_equal(-1, compile("-1"))
      # assert_equal 0x10, compile("0x10")
      # assert_equal 0b10, compile("0b10")
      # assert_equal 0o10, compile("0o10")
      # assert_equal 010, compile("010")
    end

    def test_NilNode
      assert_nil compile("nil")
    end

    def test_SelfNode
      assert_equal TOPLEVEL_BINDING.eval("self"), compile("self")
    end

    def test_TrueNode
      assert_equal true, compile("true")
    end

    ############################################################################
    # Reads                                                                    #
    ############################################################################

    def test_ClassVariableReadNode
      assert_equal 1, compile("class YARP::CompilerTest; @@yct = 1; @@yct; end")
    end

    def test_ConstantPathNode
      assert_equal YARP::CompilerTest, compile("YARP::CompilerTest")
    end

    def test_ConstantReadNode
      assert_equal YARP, compile("YARP")
    end

    def test_GlobalVariableReadNode
      assert_equal 1, compile("$yct = 1; $yct")
    end

    def test_InstanceVariableReadNode
      assert_equal 1, compile("class YARP::CompilerTest; @yct = 1; @yct; end")
    end

    def test_LocalVariableReadNode
      assert_equal 1, compile("yct = 1; yct")
    end

    ############################################################################
    # Writes                                                                   #
    ############################################################################

    def test_ClassVariableWriteNode
      assert_equal 1, compile("class YARP::CompilerTest; @@yct = 1; end")
    end

    def test_ClassVariableAndWriteNode
      assert_equal 1, compile("class YARP::CompilerTest; @@yct = 0; @@yct &&= 1; end")
    end

    def test_ClassVariableOrWriteNode
      assert_equal 1, compile("class YARP::CompilerTest; @@yct = 1; @@yct ||= 0; end")
      assert_equal 1, compile("class YARP::CompilerTest; @@yct = nil; @@yct ||= 1; end")
    end

    def test_ClassVariableOperatorWriteNode
      assert_equal 1, compile("class YARP::CompilerTest; @@yct = 0; @@yct += 1; end")
    end

    def test_ConstantWriteNode
      constant_name = "YCT"
      assert_equal 1, compile("#{constant_name} = 1")
      # We remove the constant to avoid assigning it mutliple
      # times if we run with `--repeat_count`
      Object.send(:remove_const, constant_name)
    end

    def test_ConstantPathWriteNode
      # assert_equal 1, compile("YARP::YCT = 1")
    end

    def test_GlobalVariableWriteNode
      assert_equal 1, compile("$yct = 1")
    end

    def test_GlobalVariableAndWriteNode
      assert_equal 1, compile("$yct = 0; $yct &&= 1")
    end

    def test_GlobalVariableOrWriteNode
      assert_equal 1, compile("$yct ||= 1")
    end

    def test_GlobalVariableOperatorWriteNode
      assert_equal 1, compile("$yct = 0; $yct += 1")
    end

    def test_InstanceVariableWriteNode
      assert_equal 1, compile("class YARP::CompilerTest; @yct = 1; end")
    end

    def test_InstanceVariableAndWriteNode
      assert_equal 1, compile("@yct = 0; @yct &&= 1")
    end

    def test_InstanceVariableOrWriteNode
      assert_equal 1, compile("@yct ||= 1")
    end

    def test_InstanceVariableOperatorWriteNode
      assert_equal 1, compile("@yct = 0; @yct += 1")
    end

    def test_LocalVariableWriteNode
      assert_equal 1, compile("yct = 1")
    end

    def test_LocalVariableAndWriteNode
      assert_equal 1, compile("yct = 0; yct &&= 1")
    end

    def test_LocalVariableOrWriteNode
      assert_equal 1, compile("yct ||= 1")
    end

    def test_LocalVariableOperatorWriteNode
      assert_equal 1, compile("yct = 0; yct += 1")
    end

    ############################################################################
    # String-likes                                                             #
    ############################################################################

    def test_EmbeddedVariableNode
      # assert_equal "1", compile('class YARP::CompilerTest; @yct = 1; "#@yct"; end')
      # assert_equal "1", compile('class YARP::CompilerTest; @@yct = 1; "#@@yct"; end')
      assert_equal "1", compile('$yct = 1; "#$yct"')
    end

    def test_InterpolatedStringNode
      assert_equal "1 1 1", compile('$yct = 1; "1 #$yct 1"')
      assert_equal "1 3 1", compile('"1 #{1 + 2} 1"')
    end

    def test_InterpolatedSymbolNode
      assert_equal :"1 1 1", compile('$yct = 1; :"1 #$yct 1"')
      assert_equal :"1 3 1", compile(':"1 #{1 + 2} 1"')
    end

    def test_StringConcatNode
      # assert_equal "YARP::CompilerTest", compile('"YARP" "::" "CompilerTest"')
    end

    def test_StringNode
      assert_equal "yct", compile('"yct"')
    end

    def test_SymbolNode
      assert_equal :yct, compile(":yct")
    end

    def test_XStringNode
      # assert_equal "yctyct", compile(<<~RUBY)
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
      assert_equal 1, compile("true && 1")
      assert_equal false, compile("false && 1")
    end

    def test_OrNode
      assert_equal true, compile("true || 1")
      assert_equal 1, compile("false || 1")
    end

    ############################################################################
    # Scopes/statements                                                        #
    ############################################################################

    def test_ParenthesesNode
      assert_equal (), compile("()")
      assert_equal (1), compile("(1)")
    end

    private

    def compile(source)
      RubyVM::InstructionSequence.compile_yarp(source).eval
    end
  end
end
