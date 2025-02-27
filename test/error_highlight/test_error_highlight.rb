require "test/unit"

require "error_highlight"
require "did_you_mean"
require "tempfile"

class ErrorHighlightTest < Test::Unit::TestCase
  ErrorHighlight::DefaultFormatter.max_snippet_width = 80

  class DummyFormatter
    def self.message_for(corrections)
      ""
    end
  end

  def setup
    if defined?(DidYouMean)
      @did_you_mean_old_formatter = DidYouMean.formatter
      DidYouMean.formatter = DummyFormatter
    end
  end

  def teardown
    if defined?(DidYouMean)
      DidYouMean.formatter = @did_you_mean_old_formatter
    end
  end

  begin
    method_not_exist
  rescue NameError
    if $!.message.include?("`")
      def preprocess(msg)
        msg
      end
    else
      def preprocess(msg)
        msg.sub("`", "'")
      end
    end
  end

  if Exception.method_defined?(:detailed_message)
    def assert_error_message(klass, expected_msg, &blk)
      omit unless klass < ErrorHighlight::CoreExt
      err = assert_raise(klass, &blk)
      spot = ErrorHighlight.spot(err)
      if spot
        assert_kind_of(Integer, spot[:first_lineno])
        assert_kind_of(Integer, spot[:first_column])
        assert_kind_of(Integer, spot[:last_lineno])
        assert_kind_of(Integer, spot[:last_column])
        assert_kind_of(String, spot[:snippet])
        assert_kind_of(Array, spot[:script_lines])
      end
      assert_equal(preprocess(expected_msg).chomp, err.detailed_message(highlight: false).sub(/ \((?:NoMethod|Name)Error\)/, ""))
    end
  else
    def assert_error_message(klass, expected_msg, &blk)
      omit unless klass < ErrorHighlight::CoreExt
      err = assert_raise(klass, &blk)
      assert_equal(preprocess(expected_msg).chomp, err.message)
    end
  end

  if begin; 1.time; rescue; $!.message.end_with?("an instance of Integer"); end
    # new message format
    NEW_MESSAGE_FORMAT = true
    NIL_RECV_MESSAGE = "nil"
    ONE_RECV_MESSAGE = "an instance of Integer"
  else
    NEW_MESSAGE_FORMAT = false
    NIL_RECV_MESSAGE = "nil:NilClass"
    ONE_RECV_MESSAGE = "1:Integer"
  end

  def test_CALL_noarg_1
    assert_error_message(NoMethodError, <<~END) do
undefined method `foo' for #{ NIL_RECV_MESSAGE }

      nil.foo + 1
         ^^^^
    END

      nil.foo + 1
    end
  end

  def test_CALL_noarg_2
    assert_error_message(NoMethodError, <<~END) do
undefined method `foo' for #{ NIL_RECV_MESSAGE }

        .foo + 1
        ^^^^
    END

      nil
        .foo + 1
    end
  end

  def test_CALL_noarg_3
    assert_error_message(NoMethodError, <<~END) do
undefined method `foo' for #{ NIL_RECV_MESSAGE }

        foo + 1
        ^^^
    END

      nil.
        foo + 1
    end
  end

  def test_CALL_noarg_4
    assert_error_message(NoMethodError, <<~END) do
undefined method `foo' for #{ NIL_RECV_MESSAGE }

      (nil).foo + 1
           ^^^^
    END

      (nil).foo + 1
    end
  end

  def test_CALL_arg_1
    assert_error_message(NoMethodError, <<~END) do
undefined method `foo' for #{ NIL_RECV_MESSAGE }

      nil.foo (42)
         ^^^^
    END

      nil.foo (42)
    end
  end

  def test_CALL_arg_2
    assert_error_message(NoMethodError, <<~END) do
undefined method `foo' for #{ NIL_RECV_MESSAGE }

        .foo (
        ^^^^
    END

      nil
        .foo (
          42
        )
    end
  end

  def test_CALL_arg_3
    assert_error_message(NoMethodError, <<~END) do
undefined method `foo' for #{ NIL_RECV_MESSAGE }

        foo (
        ^^^
    END

      nil.
        foo (
          42
        )
    end
  end

  def test_CALL_arg_4
    assert_error_message(NoMethodError, <<~END) do
undefined method `foo' for #{ NIL_RECV_MESSAGE }

      nil.foo(42)
         ^^^^
    END

      nil.foo(42)
    end
  end

  def test_CALL_arg_5
    assert_error_message(NoMethodError, <<~END) do
undefined method `foo' for #{ NIL_RECV_MESSAGE }

        .foo(
        ^^^^
    END

      nil
        .foo(
          42
        )
    end
  end

  def test_CALL_arg_6
    assert_error_message(NoMethodError, <<~END) do
undefined method `foo' for #{ NIL_RECV_MESSAGE }

        foo(
        ^^^
    END

      nil.
        foo(
          42
        )
    end
  end

  def test_CALL_arg_7
    assert_error_message(ArgumentError, <<~END) do
tried to create Proc object without a block (ArgumentError)
    END

      Proc.new
    end
  end

  def test_QCALL_1
    assert_error_message(NoMethodError, <<~END) do
undefined method `foo' for #{ ONE_RECV_MESSAGE }

      1&.foo
       ^^^^^
    END

      1&.foo
    end
  end

  def test_QCALL_2
    assert_error_message(NoMethodError, <<~END) do
undefined method `foo' for #{ ONE_RECV_MESSAGE }

      1&.foo(42)
       ^^^^^
    END

      1&.foo(42)
    end
  end

  def test_CALL_aref_1
    assert_error_message(NoMethodError, <<~END) do
undefined method `[]' for #{ NIL_RECV_MESSAGE }

      nil [ ]
          ^^^
    END

      nil [ ]
    end
  end

  def test_CALL_aref_2
    assert_error_message(NoMethodError, <<~END) do
undefined method `[]' for #{ NIL_RECV_MESSAGE }

      nil [0]
          ^^^
    END

      nil [0]
    end
  end

  def test_CALL_aref_3
    assert_error_message(NoMethodError, <<~END) do
undefined method `[]' for #{ NIL_RECV_MESSAGE }
    END

      nil [
        0
      ]
    end
  end

  def test_CALL_aref_4
    v = Object.new
    recv = NEW_MESSAGE_FORMAT ? "an instance of Object" : v.inspect
    assert_error_message(NoMethodError, <<~END) do
undefined method `[]' for #{ recv }

      v &.[](0)
        ^^^^
    END

      v &.[](0)
    end
  end

  def test_CALL_aref_5
    assert_error_message(NoMethodError, <<~END) do
undefined method `[]' for #{ NIL_RECV_MESSAGE }

      (nil)[ ]
           ^^^
    END

      (nil)[ ]
    end
  end

  def test_CALL_aset
    assert_error_message(NoMethodError, <<~END) do
undefined method `[]=' for #{ NIL_RECV_MESSAGE }

      nil.[]=
         ^^^^
    END

      nil.[]=
    end
  end

  def test_CALL_op_asgn
    v = nil
    assert_error_message(NoMethodError, <<~END) do
undefined method `+' for #{ NIL_RECV_MESSAGE }

      v += 42
        ^
    END

      v += 42
    end
  end

  def test_CALL_special_call_1
    assert_error_message(NoMethodError, <<~END) do
undefined method `call' for #{ NIL_RECV_MESSAGE }
    END

      nil.()
    end
  end

  def test_CALL_special_call_2
    assert_error_message(NoMethodError, <<~END) do
undefined method `call' for #{ NIL_RECV_MESSAGE }
    END

      nil.(42)
    end
  end

  def test_CALL_send
    assert_error_message(NoMethodError, <<~END) do
undefined method `foo' for #{ NIL_RECV_MESSAGE }

      nil.send(:foo, 42)
         ^^^^^
    END

      nil.send(:foo, 42)
    end
  end

  def test_ATTRASGN_1
    assert_error_message(NoMethodError, <<~END) do
undefined method `[]=' for #{ NIL_RECV_MESSAGE }

      nil [ ] = 42
          ^^^^^
    END

      nil [ ] = 42
    end
  end

  def test_ATTRASGN_2
    assert_error_message(NoMethodError, <<~END) do
undefined method `[]=' for #{ NIL_RECV_MESSAGE }

      nil [0] = 42
          ^^^^^
    END

      nil [0] = 42
    end
  end

  def test_ATTRASGN_3
    assert_error_message(NoMethodError, <<~END) do
undefined method `foo=' for #{ NIL_RECV_MESSAGE }

      nil.foo = 42
         ^^^^^^
    END

      nil.foo = 42
    end
  end

  def test_ATTRASGN_4
    assert_error_message(NoMethodError, <<~END) do
undefined method `[]=' for #{ NIL_RECV_MESSAGE }

      (nil)[0] = 42
           ^^^^^
    END

      (nil)[0] = 42
    end
  end

  def test_ATTRASGN_5
    assert_error_message(NoMethodError, <<~END) do
undefined method `foo=' for #{ NIL_RECV_MESSAGE }

      (nil).foo = 42
           ^^^^^^
    END

      (nil).foo = 42
    end
  end

  def test_OPCALL_binary_1
    assert_error_message(NoMethodError, <<~END) do
undefined method `+' for #{ NIL_RECV_MESSAGE }

      nil + 42
          ^
    END

      nil + 42
    end
  end

  def test_OPCALL_binary_2
    assert_error_message(NoMethodError, <<~END) do
undefined method `+' for #{ NIL_RECV_MESSAGE }

      nil + # comment
          ^
    END

      nil + # comment
        42
    end
  end

  def test_OPCALL_binary_3
    assert_error_message(NoMethodError, <<~END) do
undefined method `+' for #{ NIL_RECV_MESSAGE }

      (nil) + 42
            ^
    END

      (nil) + 42
    end
  end

  def test_OPCALL_unary_1
    assert_error_message(NoMethodError, <<~END) do
undefined method `+@' for #{ NIL_RECV_MESSAGE }

      + nil
      ^
    END

      + nil
    end
  end

  def test_OPCALL_unary_2
    assert_error_message(NoMethodError, <<~END) do
undefined method `+@' for #{ NIL_RECV_MESSAGE }

      +(nil)
      ^
    END

      +(nil)
    end
  end

  def test_FCALL_1
    assert_error_message(NoMethodError, <<~END) do
undefined method `foo' for #{ NIL_RECV_MESSAGE }

      nil.instance_eval { foo() }
                          ^^^
    END

      nil.instance_eval { foo() }
    end
  end

  def test_FCALL_2
    assert_error_message(NoMethodError, <<~END) do
undefined method `foo' for #{ NIL_RECV_MESSAGE }

      nil.instance_eval { foo(42) }
                          ^^^
    END

      nil.instance_eval { foo(42) }
    end
  end

  def test_VCALL_2
    assert_error_message(NameError, <<~END) do
undefined local variable or method `foo' for #{ NIL_RECV_MESSAGE }

      nil.instance_eval { foo }
                          ^^^
    END

      nil.instance_eval { foo }
    end
  end

  def test_OP_ASGN1_aref_1
    v = nil

    assert_error_message(NoMethodError, <<~END) do
undefined method `[]' for #{ NIL_RECV_MESSAGE }

      v [0] += 42
        ^^^
    END

      v [0] += 42
    end
  end

  def test_OP_ASGN1_aref_2
    v = nil

    assert_error_message(NoMethodError, <<~END) do
undefined method `[]' for #{ NIL_RECV_MESSAGE }

      v [0] += # comment
        ^^^
    END

      v [0] += # comment
        42
    end
  end

  def test_OP_ASGN1_aref_3
    v = nil

    assert_error_message(NoMethodError, <<~END) do
undefined method `[]' for #{ NIL_RECV_MESSAGE }
    END

      v [
        0
      ] += # comment
        42
    end
  end

  def test_OP_ASGN1_aref_4
    v = nil

    assert_error_message(NoMethodError, <<~END) do
undefined method `[]' for #{ NIL_RECV_MESSAGE }

      (v)[0] += 42
         ^^^
    END

      (v)[0] += 42
    end
  end

  def test_OP_ASGN1_op_1
    v = Object.new
    def v.[](x); nil; end

    assert_error_message(NoMethodError, <<~END) do
undefined method `+' for #{ NIL_RECV_MESSAGE }

      v [0] += 42
            ^
    END

      v [0] += 42
    end
  end

  def test_OP_ASGN1_op_2
    v = Object.new
    def v.[](x); nil; end

    assert_error_message(NoMethodError, <<~END) do
undefined method `+' for #{ NIL_RECV_MESSAGE }

      v [0 ] += # comment
             ^
    END

      v [0 ] += # comment
        42
    end
  end

  def test_OP_ASGN1_op_3
    v = Object.new
    def v.[](x); nil; end

    assert_error_message(NoMethodError, <<~END) do
undefined method `+' for #{ NIL_RECV_MESSAGE }
    END

      v [
        0
      ] +=
        42
    end
  end

  def test_OP_ASGN1_op_4
    v = Object.new
    def v.[](x); nil; end

    assert_error_message(NoMethodError, <<~END) do
undefined method `+' for #{ NIL_RECV_MESSAGE }

      (v)[0] += 42
             ^
    END

      (v)[0] += 42
    end
  end

  def test_OP_ASGN1_aset_1
    v = Object.new
    def v.[](x); 1; end

    assert_error_message(NoMethodError, <<~END) do
undefined method `[]=' for #{ v.inspect }

      v [0] += 42
        ^^^^^^
    END

      v [0] += 42
    end
  end

  def test_OP_ASGN1_aset_2
    v = Object.new
    def v.[](x); 1; end

    assert_error_message(NoMethodError, <<~END) do
undefined method `[]=' for #{ v.inspect }

      v [0] += # comment
        ^^^^^^
    END

      v [0] += # comment
        42
    end
  end

  def test_OP_ASGN1_aset_3
    v = Object.new
    def v.[](x); 1; end

    assert_error_message(NoMethodError, <<~END) do
undefined method `[]=' for #{ v.inspect }
    END

      v [
        0
      ] +=
        42
    end
  end

  def test_OP_ASGN1_aset_4
    v = Object.new
    def v.[](x); 1; end

    assert_error_message(NoMethodError, <<~END) do
undefined method `[]=' for #{ v.inspect }

      (v)[0] += 42
         ^^^^^^
    END

      (v)[0] += 42
    end
  end

  def test_OP_ASGN2_read_1
    v = nil

    assert_error_message(NoMethodError, <<~END) do
undefined method `foo' for #{ NIL_RECV_MESSAGE }

      v.foo += 42
       ^^^^
    END

      v.foo += 42
    end
  end

  def test_OP_ASGN2_read_2
    v = nil

    assert_error_message(NoMethodError, <<~END) do
undefined method `foo' for #{ NIL_RECV_MESSAGE }

      v.foo += # comment
       ^^^^
    END

      v.foo += # comment
        42
    end
  end

  def test_OP_ASGN2_read_3
    v = nil

    assert_error_message(NoMethodError, <<~END) do
undefined method `foo' for #{ NIL_RECV_MESSAGE }

      (v).foo += 42
         ^^^^
    END

      (v).foo += 42
    end
  end

  def test_OP_ASGN2_op_1
    v = Object.new
    def v.foo; nil; end

    assert_error_message(NoMethodError, <<~END) do
undefined method `+' for #{ NIL_RECV_MESSAGE }

      v.foo += 42
            ^
    END

      v.foo += 42
    end
  end

  def test_OP_ASGN2_op_2
    v = Object.new
    def v.foo; nil; end

    assert_error_message(NoMethodError, <<~END) do
undefined method `+' for #{ NIL_RECV_MESSAGE }

      v.foo += # comment
            ^
    END

      v.foo += # comment
        42
    end
  end

  def test_OP_ASGN2_op_3
    v = Object.new
    def v.foo; nil; end

    assert_error_message(NoMethodError, <<~END) do
undefined method `+' for #{ NIL_RECV_MESSAGE }

      (v).foo += 42
              ^
    END

      (v).foo += 42
    end
  end

  def test_OP_ASGN2_write_1
    v = Object.new
    def v.foo; 1; end

    assert_error_message(NoMethodError, <<~END) do
undefined method `foo=' for #{ v.inspect }

      v.foo += 42
       ^^^^^^^
    END

      v.foo += 42
    end
  end

  def test_OP_ASGN2_write_2
    v = Object.new
    def v.foo; 1; end

    assert_error_message(NoMethodError, <<~END) do
undefined method `foo=' for #{ v.inspect }

      v.foo += # comment
       ^^^^^^^
    END

      v.foo += # comment
        42
    end
  end

  def test_OP_ASGN2_write_3
    v = Object.new
    def v.foo; 1; end

    assert_error_message(NoMethodError, <<~END) do
undefined method `foo=' for #{ v.inspect }

      (v).foo += 42
         ^^^^^^^
    END

      (v).foo += 42
    end
  end

  def test_CONST
    assert_error_message(NameError, <<~END) do
uninitialized constant ErrorHighlightTest::NotDefined

      1 + NotDefined + 1
          ^^^^^^^^^^
    END

      1 + NotDefined + 1
    end
  end

  def test_COLON2_1
    assert_error_message(NameError, <<~END) do
uninitialized constant ErrorHighlightTest::NotDefined

      ErrorHighlightTest::NotDefined
                        ^^^^^^^^^^^^
    END

      ErrorHighlightTest::NotDefined
    end
  end

  def test_COLON2_2
    assert_error_message(NameError, <<~END) do
uninitialized constant ErrorHighlightTest::NotDefined

        NotDefined
        ^^^^^^^^^^
    END

      ErrorHighlightTest::
        NotDefined
    end
  end

  def test_COLON2_3
    assert_error_message(NameError, <<~END) do
uninitialized constant ErrorHighlightTest::NotDefined

      ErrorHighlightTest::NotDefined::Foo
                        ^^^^^^^^^^^^
    END

      ErrorHighlightTest::NotDefined::Foo
    end
  end

  def test_COLON2_4
    assert_error_message(NameError, <<~END) do
uninitialized constant ErrorHighlightTest::NotDefined

      ::ErrorHighlightTest::NotDefined::Foo
                          ^^^^^^^^^^^^
    END

      ::ErrorHighlightTest::NotDefined::Foo
    end
  end

  if ErrorHighlight.const_get(:Spotter).const_get(:OPT_GETCONSTANT_PATH)
    def test_COLON2_5
      # Unfortunately, we cannot identify which `NotDefined` caused the NameError
      assert_error_message(NameError, <<~END) do
  uninitialized constant ErrorHighlightTest::NotDefined
      END

        ErrorHighlightTest::NotDefined::NotDefined
      end
    end
  else
    def test_COLON2_5
      assert_error_message(NameError, <<~END) do
uninitialized constant ErrorHighlightTest::NotDefined

        ErrorHighlightTest::NotDefined::NotDefined
                          ^^^^^^^^^^^^
      END

        ErrorHighlightTest::NotDefined::NotDefined
      end
    end
  end

  def test_COLON3
    assert_error_message(NameError, <<~END) do
uninitialized constant NotDefined

      ::NotDefined
      ^^^^^^^^^^^^
    END

      ::NotDefined
    end
  end

  module OP_CDECL_TEST
    Nil = nil
  end

  def test_OP_CDECL_read_1
    assert_error_message(NameError, <<~END) do
uninitialized constant ErrorHighlightTest::OP_CDECL_TEST::NotDefined

      OP_CDECL_TEST::NotDefined += 1
                   ^^^^^^^^^^^^
    END

      OP_CDECL_TEST::NotDefined += 1
    end
  end

  def test_OP_CDECL_read_2
    assert_error_message(NameError, <<~END) do
uninitialized constant ErrorHighlightTest::OP_CDECL_TEST::NotDefined

      OP_CDECL_TEST::NotDefined += # comment
                   ^^^^^^^^^^^^
    END

      OP_CDECL_TEST::NotDefined += # comment
        1
    end
  end

  def test_OP_CDECL_read_3
    assert_error_message(NameError, <<~END) do
uninitialized constant ErrorHighlightTest::OP_CDECL_TEST::NotDefined
    END

      OP_CDECL_TEST::
        NotDefined += 1
    end
  end

  def test_OP_CDECL_op_1
    assert_error_message(NoMethodError, <<~END) do
undefined method `+' for #{ NIL_RECV_MESSAGE }

      OP_CDECL_TEST::Nil += 1
                         ^
    END

      OP_CDECL_TEST::Nil += 1
    end
  end

  def test_OP_CDECL_op_2
    assert_error_message(NoMethodError, <<~END) do
undefined method `+' for #{ NIL_RECV_MESSAGE }

      OP_CDECL_TEST::Nil += # comment
                         ^
    END

      OP_CDECL_TEST::Nil += # comment
        1
    end
  end

  def test_OP_CDECL_op_3
    assert_error_message(NoMethodError, <<~END) do
undefined method `+' for #{ NIL_RECV_MESSAGE }

        Nil += 1
            ^
    END

      OP_CDECL_TEST::
        Nil += 1
    end
  end

  def test_OP_CDECL_toplevel_1
    assert_error_message(NameError, <<~END) do
uninitialized constant NotDefined

      ::NotDefined += 1
      ^^^^^^^^^^^^
    END

      ::NotDefined += 1
    end
  end

  def test_OP_CDECL_toplevel_2
    recv = NEW_MESSAGE_FORMAT ? "class ErrorHighlightTest" : "ErrorHighlightTest:Class"
    assert_error_message(NoMethodError, <<~END) do
undefined method `+' for #{ recv }

      ::ErrorHighlightTest += 1
                           ^
    END

      ::ErrorHighlightTest += 1
    end
  end

  def test_explicit_raise_name_error
    assert_error_message(NameError, <<~END) do
NameError

      raise NameError
      ^^^^^
    END

      raise NameError
    end
  end

  def test_explicit_raise_no_method_error
    assert_error_message(NoMethodError, <<~END) do
NoMethodError

      raise NoMethodError
      ^^^^^
    END

      raise NoMethodError
    end
  end

  def test_const_get
    assert_error_message(NameError, <<~END) do
uninitialized constant ErrorHighlightTest::NotDefined

      ErrorHighlightTest.const_get(:NotDefined)
                        ^^^^^^^^^^
    END

      ErrorHighlightTest.const_get(:NotDefined)
    end
  end

  def test_local_variable_get
    b = binding
    assert_error_message(NameError, <<~END) do
local variable `foo' is not defined for #{ b.inspect }

      b.local_variable_get(:foo)
       ^^^^^^^^^^^^^^^^^^^
    END

      b.local_variable_get(:foo)
    end
  end

  def test_multibyte
    assert_error_message(NoMethodError, <<~END) do
undefined method `あいうえお' for #{ NIL_RECV_MESSAGE }
    END

      nil.あいうえお
    end
  end

  def test_args_CALL_1
    assert_error_message(TypeError, <<~END) do
nil can't be coerced into Integer (TypeError)

      1.+(nil)
          ^^^
    END

      1.+(nil)
    end
  end

  def test_args_CALL_2
    v = []
    assert_error_message(TypeError, <<~END) do
no implicit conversion from nil to integer (TypeError)

      v[nil]
        ^^^
    END

      v[nil]
    end
  end

  def test_args_ATTRASGN_1
    v = []
    assert_error_message(ArgumentError, <<~END) do
wrong number of arguments (given 1, expected 2..3) (ArgumentError)

      v [ ] = 1
         ^^^^^^
    END

      v [ ] = 1
    end
  end

  def test_args_ATTRASGN_2
    v = []
    assert_error_message(TypeError, <<~END) do
no implicit conversion from nil to integer (TypeError)

      v [nil] = 1
         ^^^^^^^^
    END

      v [nil] = 1
    end
  end

  def test_args_ATTRASGN_3
    assert_error_message(TypeError, <<~END) do
no implicit conversion of String into Integer (TypeError)

      $stdin.lineno = "str"
                      ^^^^^
    END

      $stdin.lineno = "str"
    end
  end

  def test_args_OPCALL
    assert_error_message(TypeError, <<~END) do
nil can't be coerced into Integer (TypeError)

      1 + nil
          ^^^
    END

      1 + nil
    end
  end

  def test_args_FCALL_1
    assert_error_message(TypeError, <<~END) do
no implicit conversion of Symbol into String (TypeError)

      "str".instance_eval { gsub("foo", :sym) }
                                 ^^^^^^^^^^^
    END

      "str".instance_eval { gsub("foo", :sym) }
    end
  end

  def test_args_FCALL_2
    assert_error_message(TypeError, <<~END) do
no implicit conversion of Symbol into String (TypeError)

      "str".instance_eval { gsub "foo", :sym }
                                 ^^^^^^^^^^^
    END

      "str".instance_eval { gsub "foo", :sym }
    end
  end

  def test_args_OP_ASGN1_aref_1
    v = []

    assert_error_message(TypeError, <<~END) do
no implicit conversion from nil to integer (TypeError)

      v [nil] += 42
         ^^^^^^^^^^
    END

      v [nil] += 42
    end
  end

  def test_args_OP_ASGN1_aref_2
    v = []

    assert_error_message(ArgumentError, <<~END) do
wrong number of arguments (given 0, expected 1..2) (ArgumentError)

      v [ ] += 42
         ^^^^^^^^
    END

      v [ ] += 42
    end
  end

  def test_args_OP_ASGN1_op
    v = [1]

    assert_error_message(TypeError, <<~END) do
nil can't be coerced into Integer (TypeError)

      v [0] += nil
         ^^^^^^^^^
    END

      v [0] += nil
    end
  end

  def test_args_OP_ASGN2
    v = Object.new
    def v.foo; 1; end

    assert_error_message(TypeError, <<~END) do
nil can't be coerced into Integer (TypeError)

      v.foo += nil
               ^^^
    END

      v.foo += nil
    end
  end

  def test_custom_formatter
    custom_formatter = Object.new
    def custom_formatter.message_for(spot)
      "\n\n" + spot.except(:script_lines).inspect
    end

    original_formatter, ErrorHighlight.formatter = ErrorHighlight.formatter, custom_formatter

    assert_error_message(NoMethodError, <<~END) do
undefined method `time' for #{ ONE_RECV_MESSAGE }

#{{ first_lineno: __LINE__ + 3, first_column: 7, last_lineno: __LINE__ + 3, last_column: 12, snippet: "      1.time {}\n" }.inspect}
    END

      1.time {}
    end

  ensure
    ErrorHighlight.formatter = original_formatter
  end

  def test_hard_tabs
    Tempfile.create(["error_highlight_test", ".rb"], binmode: true) do |tmp|
      tmp << "\t \t1.time {}\n"
      tmp.close

      assert_error_message(NoMethodError, <<~END.gsub("_", "\t")) do
undefined method `time' for #{ ONE_RECV_MESSAGE }

_ _1.time {}
_ _ ^^^^^
    END

        load tmp.path
      end
    end
  end

  def test_no_final_newline
    Tempfile.create(["error_highlight_test", ".rb"], binmode: true) do |tmp|
      tmp << "1.time {}"
      tmp.close

      assert_error_message(NoMethodError, <<~END) do
undefined method `time' for #{ ONE_RECV_MESSAGE }

1.time {}
 ^^^^^
    END

        load tmp.path
      end
    end
  end

  def test_errors_on_small_terminal_window_at_the_end
    assert_error_message(NoMethodError, <<~END) do
undefined method `time' for #{ ONE_RECV_MESSAGE }

...0000000000000000000000000000000000000000000000000000000000000000 + 1.time {}
                                                                       ^^^^^
    END

    100000000000000000000000000000000000000000000000000000000000000000000000000000 + 1.time {}
    end
  end

  def test_errors_on_small_terminal_window_at_the_beginning
    assert_error_message(NoMethodError, <<~END) do
undefined method `time' for #{ ONE_RECV_MESSAGE }

      1.time { 10000000000000000000000000000000000000000000000000000000000000...
       ^^^^^
    END

      1.time { 100000000000000000000000000000000000000000000000000000000000000000000000000000 }

    end
  end

  def test_errors_on_small_terminal_window_at_the_middle_near_beginning
    assert_error_message(NoMethodError, <<~END) do
undefined method `time' for #{ ONE_RECV_MESSAGE }

    100000000000000000000000000000000000000 + 1.time { 1000000000000000000000...
                                               ^^^^^
    END

    100000000000000000000000000000000000000 + 1.time { 100000000000000000000000000000000000000 }
    end
  end

  def test_errors_on_small_terminal_window_at_the_middle
    assert_error_message(NoMethodError, <<~END) do
undefined method `time' for #{ ONE_RECV_MESSAGE }

...000000000000000000000000000000000 + 1.time { 10000000000000000000000000000...
                                        ^^^^^
    END

    10000000000000000000000000000000000000000000000000000000000000000000000 + 1.time { 1000000000000000000000000000000 }
    end
  end

  def test_errors_on_extremely_small_terminal_window
    custom_max_width = 30
    original_max_width = ErrorHighlight::DefaultFormatter.max_snippet_width

    ErrorHighlight::DefaultFormatter.max_snippet_width = custom_max_width

    assert_error_message(NoMethodError, <<~END) do
undefined method `time' for #{ ONE_RECV_MESSAGE }

...00000000 + 1.time { 1000...
               ^^^^^
    END

      100000000000000 + 1.time { 100000000000000 }
    end
  ensure
    ErrorHighlight::DefaultFormatter.max_snippet_width = original_max_width
  end

  def test_errors_on_terminal_window_smaller_than_min_width
    custom_max_width = 5
    original_max_width = ErrorHighlight::DefaultFormatter.max_snippet_width
    min_snippet_width = ErrorHighlight::DefaultFormatter::MIN_SNIPPET_WIDTH

    warning = nil
    original_warn = Warning.instance_method(:warn)
    Warning.class_eval do
      remove_method(:warn)
      define_method(:warn) {|str| warning = str}
    end
    begin
      ErrorHighlight::DefaultFormatter.max_snippet_width = custom_max_width
    ensure
      Warning.class_eval do
        remove_method(:warn)
        define_method(:warn, original_warn)
      end
    end
    assert_match "'max_snippet_width' adjusted to minimum value of #{min_snippet_width}", warning

    assert_error_message(NoMethodError, <<~END) do
undefined method `time' for #{ ONE_RECV_MESSAGE }

...000 + 1.time {...
          ^^^^^
    END

    100000000000000 + 1.time { 100000000000000 }
    end
  ensure
    ErrorHighlight::DefaultFormatter.max_snippet_width = original_max_width
  end

  def test_errors_on_terminal_window_when_truncation_is_disabled
    custom_max_width = nil
    original_max_width = ErrorHighlight::DefaultFormatter.max_snippet_width

    ErrorHighlight::DefaultFormatter.max_snippet_width = custom_max_width

    assert_error_message(NoMethodError, <<~END) do
undefined method `time' for #{ ONE_RECV_MESSAGE }

      10000000000000000000000000000000000000000000000000000000000000000000000 + 1.time { 1000000000000000000000000000000 }
                                                                                 ^^^^^
    END

      10000000000000000000000000000000000000000000000000000000000000000000000 + 1.time { 1000000000000000000000000000000 }
    end
  ensure
    ErrorHighlight::DefaultFormatter.max_snippet_width = original_max_width
  end

  def test_errors_on_small_terminal_window_when_larger_than_viewport
    assert_error_message(NoMethodError, <<~END) do
undefined method `timessssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss!' for #{ ONE_RECV_MESSAGE }

      1.timesssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss...
       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    END

      1.timessssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss!
    end
  end

  def test_errors_on_small_terminal_window_when_exact_size_of_viewport
    assert_error_message(NoMethodError, <<~END) do
undefined method `timessssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss!' for #{ ONE_RECV_MESSAGE }

      1.timessssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss!...
       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    END

      1.timessssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss! * 1000
    end
  end

  def test_simulate_funcallv_from_embedded_ruby
    assert_error_message(NoMethodError, <<~END) do
undefined method `foo' for #{ NIL_RECV_MESSAGE }
    END

      nil.foo + 1
    rescue NoMethodError => exc
      def exc.backtrace_locations = []
      raise
    end
  end

  def test_spoofed_filename
    Tempfile.create(["error_highlight_test", ".rb"], binmode: true) do |tmp|
      tmp << "module Dummy\nend\n"
      tmp.close

      recv = NEW_MESSAGE_FORMAT ? "an instance of String" : '"dummy":String'
      assert_error_message(NameError, <<~END) do
        undefined local variable or method `foo' for #{ recv }
      END

        "dummy".instance_eval do
          eval <<-END, nil, tmp.path
            foo
          END
        end
      end
    end
  end

  def raise_name_error
    1.time
  end

  def test_spot_with_backtrace_location
    lineno = __LINE__
    begin
      raise_name_error
    rescue NameError => exc
    end

    spot = ErrorHighlight.spot(exc).except(:script_lines)
    assert_equal(lineno - 4, spot[:first_lineno])
    assert_equal(lineno - 4, spot[:last_lineno])
    assert_equal(5, spot[:first_column])
    assert_equal(10, spot[:last_column])
    assert_equal("    1.time\n", spot[:snippet])

    spot = ErrorHighlight.spot(exc, backtrace_location: exc.backtrace_locations[1]).except(:script_lines)
    assert_equal(lineno + 2, spot[:first_lineno])
    assert_equal(lineno + 2, spot[:last_lineno])
    assert_equal(6, spot[:first_column])
    assert_equal(22, spot[:last_column])
    assert_equal("      raise_name_error\n", spot[:snippet])
  end

  def test_spot_with_node
    omit unless RubyVM::AbstractSyntaxTree.respond_to?(:node_id_for_backtrace_location)

    # We can't revisit instruction sequences to find node ids if the prism
    # compiler was used instead of the parse.y compiler. In that case, we'll
    # omit some tests.
    omit if RubyVM::InstructionSequence.compile("").to_a[4][:parser] == :prism

    begin
      raise_name_error
    rescue NameError => exc
    end

    bl = exc.backtrace_locations.first
    expected_spot = ErrorHighlight.spot(exc, backtrace_location: bl)
    ast = RubyVM::AbstractSyntaxTree.parse_file(__FILE__, keep_script_lines: true)
    node_id = RubyVM::AbstractSyntaxTree.node_id_for_backtrace_location(bl)
    node = find_node_by_id(ast, node_id)
    actual_spot = ErrorHighlight.spot(node)

    assert_equal expected_spot, actual_spot
  end

  private

  def find_node_by_id(node, node_id)
    return node if node.node_id == node_id

    node.children.each do |child|
      next unless child.is_a?(RubyVM::AbstractSyntaxTree::Node)
      found = find_node_by_id(child, node_id)
      return found if found
    end

    return false
  end
end
