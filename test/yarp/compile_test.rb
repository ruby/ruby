# frozen_string_literal: true

require "test_helper"

class CompileTest < Test::Unit::TestCase
  test "AliasNode" do
    assert_compiles("alias foo bar")
  end

  test "AndNode" do
    assert_compiles("true && false")
  end

  test "ArrayNode" do
    assert_compiles("[]")
    assert_compiles("[foo, bar, baz]")
  end

  test "AssocNode" do
    assert_compiles("{ foo: bar }")
  end

  test "BlockNode" do
    assert_compiles("foo { bar }")
  end

  test "BlockNode with optionals" do
    assert_compiles("foo { |x = 1| bar }")
  end

  test "CallNode" do
    assert_compiles("foo")
    assert_compiles("foo(bar)")
  end

  test "ClassVariableReadNode" do
    assert_compiles("@@foo")
  end

  test "ClassVariableWriteNode" do
    assert_compiles("@@foo = 1")
  end

  test "FalseNode" do
    assert_compiles("false")
  end

  test "GlobalVariableReadNode" do
    assert_compiles("$foo")
  end

  test "GlobalVariableWriteNode" do
    assert_compiles("$foo = 1")
  end

  test "HashNode" do
    assert_compiles("{ foo: bar }")
  end

  test "InstanceVariableReadNode" do
    assert_compiles("@foo")
  end

  test "InstanceVariableWriteNode" do
    assert_compiles("@foo = 1")
  end

  test "IntegerNode" do
    assert_compiles("1")
    assert_compiles("1_000")
  end

  test "InterpolatedStringNode" do
    assert_compiles("\"foo \#{bar} baz\"")
  end

  test "LocalVariableWriteNode" do
    assert_compiles("foo = 1")
  end

  test "LocalVariableReadNode" do
    assert_compiles("[foo = 1, foo]")
  end

  test "NilNode" do
    assert_compiles("nil")
  end

  test "OrNode" do
    assert_compiles("true || false")
  end

  test "ParenthesesNode" do
    assert_compiles("()")
  end

  test "ProgramNode" do
    assert_compiles("")
  end

  test "RangeNode" do
    assert_compiles("foo..bar")
    assert_compiles("foo...bar")
    assert_compiles("(foo..)")
    assert_compiles("(foo...)")
    assert_compiles("(..bar)")
    assert_compiles("(...bar)")
  end

  test "SelfNode" do
    assert_compiles("self")
  end

  test "StringNode" do
    assert_compiles("\"foo\"")
  end

  test "SymbolNode" do
    assert_compiles(":foo")
  end

  test "TrueNode" do
    assert_compiles("true")
  end

  test "UndefNode" do
    assert_compiles("undef :foo, :bar, :baz")
  end

  test "XStringNode" do
    assert_compiles("`foo`")
  end

  private

  def assert_compiles(source)
    assert_equal_iseqs(rubyvm_compile(source), YARP.compile(source))
  end

  # Instruction sequences have 13 elements in their lists. We don't currently
  # support all of the fields, so we can't compare the iseqs directly. Instead,
  # we compare the elements that we do support.
  def assert_equal_iseqs(expected, actual)
    # The first element is the magic comment string.
    assert_equal expected[0], actual[0]

    # The next three elements are the major, minor, and patch version numbers.
    assert_equal expected[1...4], actual[1...4]

    # The next element is a set of options for the iseq. It has lots of
    # different information, some of which we support and some of which we
    # don't.
    assert_equal expected[4][:arg_size], actual[4][:arg_size], "Unexpected difference in arg_size"
    assert_equal expected[4][:stack_max], actual[4][:stack_max], "Unexpected difference in stack_max"

    assert_kind_of Integer, actual[4][:local_size]
    assert_kind_of Integer, actual[4][:node_id]

    assert_equal expected[4][:code_location].length, actual[4][:code_location].length, "Unexpected difference in code_location length"
    assert_equal expected[4][:node_ids].length, actual[4][:node_ids].length, "Unexpected difference in node_ids length"

    # Then we have the name of the iseq, the relative file path, the absolute
    # file path, and the line number. We don't have this working quite yet.
    assert_kind_of String, actual[5]
    assert_kind_of String, actual[6]
    assert_kind_of String, actual[7]
    assert_kind_of Integer, actual[8]

    # Next we have the type of the iseq.
    assert_equal expected[9], actual[9]

    # Next we have the list of local variables. We don't support this yet.
    assert_kind_of Array, actual[10]

    # Next we have the argument options. These are used in block and method
    # iseqs to reflect how the arguments are passed.
    assert_equal expected[11], actual[11], "Unexpected difference in argument options"

    # Next we have the catch table entries. We don't have this working yet.
    assert_kind_of Array, actual[12]

    # Finally we have the actual instructions. We support some of this, but omit
    # line numbers and some tracepoint events.
    expected[13].each do |insn|
      case insn
      in [:send, opnds, expected_block] unless expected_block.nil?
        actual[13].shift => [:send, ^(opnds), actual_block]
        assert_equal_iseqs expected_block, actual_block
      in Array | :RUBY_EVENT_B_CALL | :RUBY_EVENT_B_RETURN | /^label_\d+/
        assert_equal insn, actual[13].shift
      in Integer | /^RUBY_EVENT_/
        # skip these for now
      else
        flunk "Unexpected instruction: #{insn.inspect}"
      end
    end
  end

  def rubyvm_compile(source)
    options = {
      peephole_optimization: false,
      specialized_instruction: false,
      operands_unification: false,
      instructions_unification: false,
      frozen_string_literal: false
    }

    RubyVM::InstructionSequence.compile(source, **options).to_a
  end
end
