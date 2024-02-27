# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class CommandLineTest < TestCase
    def test_command_line_p
      program = Prism.parse("1", command_line_p: true).value
      statements = program.statements.body

      assert_equal 2, statements.length
      assert_kind_of CallNode, statements.last
      assert_equal :print, statements.last.name
    end

    def test_command_line_n
      program = Prism.parse("1", command_line_n: true).value
      statements = program.statements.body

      assert_equal 1, statements.length
      assert_kind_of WhileNode, statements.first

      predicate = statements.first.predicate
      assert_kind_of CallNode, predicate
      assert_equal :gets, predicate.name

      arguments = predicate.arguments.arguments
      assert_equal 1, arguments.length
      assert_equal :$/, arguments.first.name
    end

    def test_command_line_a
      program = Prism.parse("1", command_line_n: true, command_line_a: true).value
      statements = program.statements.body

      assert_equal 1, statements.length
      assert_kind_of WhileNode, statements.first

      statement = statements.first.statements.body.first
      assert_kind_of GlobalVariableWriteNode, statement
      assert_equal :$F, statement.name
    end

    def test_command_line_l
      program = Prism.parse("1", command_line_n: true, command_line_l: true).value
      statements = program.statements.body

      assert_equal 1, statements.length
      assert_kind_of WhileNode, statements.first

      predicate = statements.first.predicate
      assert_kind_of CallNode, predicate
      assert_equal :gets, predicate.name

      arguments = predicate.arguments.arguments
      assert_equal 2, arguments.length
      assert_equal :$/, arguments.first.name
      assert_equal "chomp", arguments.last.elements.first.key.unescaped
    end
  end
end
