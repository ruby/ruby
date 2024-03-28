# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class RubyAPITest < TestCase
    if !ENV["PRISM_BUILD_MINIMAL"]
      def test_ruby_api
        filepath = __FILE__
        source = File.read(filepath, binmode: true, external_encoding: Encoding::UTF_8)

        assert_equal Prism.lex(source, filepath: filepath).value, Prism.lex_file(filepath).value
        assert_equal Prism.dump(source, filepath: filepath), Prism.dump_file(filepath)

        serialized = Prism.dump(source, filepath: filepath)
        ast1 = Prism.load(source, serialized).value
        ast2 = Prism.parse(source, filepath: filepath).value
        ast3 = Prism.parse_file(filepath).value

        assert_equal_nodes ast1, ast2
        assert_equal_nodes ast2, ast3
      end
    end

    def test_parse_success?
      assert Prism.parse_success?("1")
      refute Prism.parse_success?("<>")
    end

    def test_parse_file_success?
      assert Prism.parse_file_success?(__FILE__)
    end

    def test_options
      assert_equal "", Prism.parse("__FILE__").value.statements.body[0].filepath
      assert_equal "foo.rb", Prism.parse("__FILE__", filepath: "foo.rb").value.statements.body[0].filepath

      assert_equal 1, Prism.parse("foo").value.statements.body[0].location.start_line
      assert_equal 10, Prism.parse("foo", line: 10).value.statements.body[0].location.start_line

      refute Prism.parse("\"foo\"").value.statements.body[0].frozen?
      assert Prism.parse("\"foo\"", frozen_string_literal: true).value.statements.body[0].frozen?
      refute Prism.parse("\"foo\"", frozen_string_literal: false).value.statements.body[0].frozen?

      assert_kind_of Prism::CallNode, Prism.parse("foo").value.statements.body[0]
      assert_kind_of Prism::LocalVariableReadNode, Prism.parse("foo", scopes: [[:foo]]).value.statements.body[0]
      assert_equal 1, Prism.parse("foo", scopes: [[:foo], []]).value.statements.body[0].depth

      assert_equal [:foo], Prism.parse("foo", scopes: [[:foo]]).value.locals
    end

    def test_literal_value_method
      assert_equal 123, parse_expression("123").value
      assert_equal 3.14, parse_expression("3.14").value
      assert_equal 42i, parse_expression("42i").value
      assert_equal 42.1ri, parse_expression("42.1ri").value
      assert_equal 3.14i, parse_expression("3.14i").value
      assert_equal 42r, parse_expression("42r").value
      assert_equal 0.5r, parse_expression("0.5r").value
      assert_equal 42ri, parse_expression("42ri").value
      assert_equal 0.5ri, parse_expression("0.5ri").value
      assert_equal 0xFFr, parse_expression("0xFFr").value
      assert_equal 0xFFri, parse_expression("0xFFri").value
    end

    def test_location_join
      recv, args_node, _ = parse_expression("1234 + 567").child_nodes
      arg = args_node.arguments[0]

      joined = recv.location.join(arg.location)
      assert_equal 0, joined.start_offset
      assert_equal 10, joined.length

      assert_raise RuntimeError, "Incompatible locations" do
        arg.location.join(recv.location)
      end

      other_arg = parse_expression("1234 + 567").arguments.arguments[0]

      assert_raise RuntimeError, "Incompatible sources" do
        other_arg.location.join(recv.location)
      end

      assert_raise RuntimeError, "Incompatible sources" do
        recv.location.join(other_arg.location)
      end
    end

    def test_location_character_offsets
      program = Prism.parse("😀 + 😀\n😍 ||= 😍").value

      # first 😀
      location = program.statements.body.first.receiver.location
      assert_equal 0, location.start_character_offset
      assert_equal 1, location.end_character_offset
      assert_equal 0, location.start_character_column
      assert_equal 1, location.end_character_column

      # second 😀
      location = program.statements.body.first.arguments.arguments.first.location
      assert_equal 4, location.start_character_offset
      assert_equal 5, location.end_character_offset
      assert_equal 4, location.start_character_column
      assert_equal 5, location.end_character_column

      # first 😍
      location = program.statements.body.last.name_loc
      assert_equal 6, location.start_character_offset
      assert_equal 7, location.end_character_offset
      assert_equal 0, location.start_character_column
      assert_equal 1, location.end_character_column

      # second 😍
      location = program.statements.body.last.value.location
      assert_equal 12, location.start_character_offset
      assert_equal 13, location.end_character_offset
      assert_equal 6, location.start_character_column
      assert_equal 7, location.end_character_column
    end

    def test_location_code_units
      program = Prism.parse("😀 + 😀\n😍 ||= 😍").value

      # first 😀
      location = program.statements.body.first.receiver.location

      assert_equal 0, location.start_code_units_offset(Encoding::UTF_8)
      assert_equal 0, location.start_code_units_offset(Encoding::UTF_16LE)
      assert_equal 0, location.start_code_units_offset(Encoding::UTF_32LE)

      assert_equal 1, location.end_code_units_offset(Encoding::UTF_8)
      assert_equal 2, location.end_code_units_offset(Encoding::UTF_16LE)
      assert_equal 1, location.end_code_units_offset(Encoding::UTF_32LE)

      assert_equal 0, location.start_code_units_column(Encoding::UTF_8)
      assert_equal 0, location.start_code_units_column(Encoding::UTF_16LE)
      assert_equal 0, location.start_code_units_column(Encoding::UTF_32LE)

      assert_equal 1, location.end_code_units_column(Encoding::UTF_8)
      assert_equal 2, location.end_code_units_column(Encoding::UTF_16LE)
      assert_equal 1, location.end_code_units_column(Encoding::UTF_32LE)

      # second 😀
      location = program.statements.body.first.arguments.arguments.first.location

      assert_equal 4, location.start_code_units_offset(Encoding::UTF_8)
      assert_equal 5, location.start_code_units_offset(Encoding::UTF_16LE)
      assert_equal 4, location.start_code_units_offset(Encoding::UTF_32LE)

      assert_equal 5, location.end_code_units_offset(Encoding::UTF_8)
      assert_equal 7, location.end_code_units_offset(Encoding::UTF_16LE)
      assert_equal 5, location.end_code_units_offset(Encoding::UTF_32LE)

      assert_equal 4, location.start_code_units_column(Encoding::UTF_8)
      assert_equal 5, location.start_code_units_column(Encoding::UTF_16LE)
      assert_equal 4, location.start_code_units_column(Encoding::UTF_32LE)

      assert_equal 5, location.end_code_units_column(Encoding::UTF_8)
      assert_equal 7, location.end_code_units_column(Encoding::UTF_16LE)
      assert_equal 5, location.end_code_units_column(Encoding::UTF_32LE)

      # first 😍
      location = program.statements.body.last.name_loc

      assert_equal 6, location.start_code_units_offset(Encoding::UTF_8)
      assert_equal 8, location.start_code_units_offset(Encoding::UTF_16LE)
      assert_equal 6, location.start_code_units_offset(Encoding::UTF_32LE)

      assert_equal 7, location.end_code_units_offset(Encoding::UTF_8)
      assert_equal 10, location.end_code_units_offset(Encoding::UTF_16LE)
      assert_equal 7, location.end_code_units_offset(Encoding::UTF_32LE)

      assert_equal 0, location.start_code_units_column(Encoding::UTF_8)
      assert_equal 0, location.start_code_units_column(Encoding::UTF_16LE)
      assert_equal 0, location.start_code_units_column(Encoding::UTF_32LE)

      assert_equal 1, location.end_code_units_column(Encoding::UTF_8)
      assert_equal 2, location.end_code_units_column(Encoding::UTF_16LE)
      assert_equal 1, location.end_code_units_column(Encoding::UTF_32LE)

      # second 😍
      location = program.statements.body.last.value.location

      assert_equal 12, location.start_code_units_offset(Encoding::UTF_8)
      assert_equal 15, location.start_code_units_offset(Encoding::UTF_16LE)
      assert_equal 12, location.start_code_units_offset(Encoding::UTF_32LE)

      assert_equal 13, location.end_code_units_offset(Encoding::UTF_8)
      assert_equal 17, location.end_code_units_offset(Encoding::UTF_16LE)
      assert_equal 13, location.end_code_units_offset(Encoding::UTF_32LE)

      assert_equal 6, location.start_code_units_column(Encoding::UTF_8)
      assert_equal 7, location.start_code_units_column(Encoding::UTF_16LE)
      assert_equal 6, location.start_code_units_column(Encoding::UTF_32LE)

      assert_equal 7, location.end_code_units_column(Encoding::UTF_8)
      assert_equal 9, location.end_code_units_column(Encoding::UTF_16LE)
      assert_equal 7, location.end_code_units_column(Encoding::UTF_32LE)
    end

    def test_heredoc?
      refute parse_expression("\"foo\"").heredoc?
      refute parse_expression("\"foo \#{1}\"").heredoc?
      refute parse_expression("`foo`").heredoc?
      refute parse_expression("`foo \#{1}`").heredoc?

      assert parse_expression("<<~HERE\nfoo\nHERE\n").heredoc?
      assert parse_expression("<<~HERE\nfoo \#{1}\nHERE\n").heredoc?
      assert parse_expression("<<~`HERE`\nfoo\nHERE\n").heredoc?
      assert parse_expression("<<~`HERE`\nfoo \#{1}\nHERE\n").heredoc?
    end

    # Through some bit hackery, we want to allow consumers to use the integer
    # base flags as the base itself. It has a nice property that the current
    # alignment provides them in the correct order. So here we test that our
    # assumption holds so that it doesn't change out from under us.
    #
    # In C, this would look something like:
    #
    #     ((flags & ~DECIMAL) << 1) || 10
    #
    # We have to do some other work in Ruby because 0 is truthy and ~ on an
    # integer doesn't have a fixed width.
    def test_integer_base_flags
      base = -> (node) do
        value = (node.send(:flags) & (0b1111 - IntegerBaseFlags::DECIMAL)) << 1
        value == 0 ? 10 : value
      end

      assert_equal 2, base[parse_expression("0b1")]
      assert_equal 8, base[parse_expression("0o1")]
      assert_equal 10, base[parse_expression("0d1")]
      assert_equal 16, base[parse_expression("0x1")]
    end

    private

    def parse_expression(source)
      Prism.parse(source).value.statements.body.first
    end
  end
end
