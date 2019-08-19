# frozen_string_literal: false
require 'test/unit'

class RubyVM
  module AST
    class Node
      class CodePosition
        include Comparable
        attr_reader :lineno, :column
        def initialize(lineno, column)
          @lineno = lineno
          @column = column
        end

        def <=>(other)
          case
          when lineno < other.lineno
            -1
          when lineno == other.lineno
            column <=> other.column
          when lineno > other.lineno
            1
          end
        end
      end

      def beg_pos
        CodePosition.new(first_lineno, first_column)
      end

      def end_pos
        CodePosition.new(last_lineno, last_column)
      end

      alias to_s inspect
    end
  end
end

class TestAst < Test::Unit::TestCase
  class Helper
    attr_reader :errors

    def initialize(path)
      @path = path
      @errors = []
      @debug = false
    end

    def validate_range
      @errors = []
      validate_range0(ast)

      @errors.empty?
    end

    def validate_not_cared
      @errors = []
      validate_not_cared0(ast)

      @errors.empty?
    end

    def ast
      return @ast if defined?(@ast)
      ast = RubyVM::AST.parse_file(@path)
      raise "Syntax error: #{@path}" if ast.nil?
      @ast = ast
    end

    private

    def validate_range0(node)
      beg_pos, end_pos = node.beg_pos, node.end_pos
      children = node.children.grep(RubyVM::AST)

      return true if children.empty?
      # These NODE_D* has NODE_ARRAY as nd_next->nd_next whose last locations
      # we can not update when item is appended.
      return true if ["NODE_DSTR", "NODE_DXSTR", "NODE_DREGX", "NODE_DSYM"].include? node.type

      min = children.map(&:beg_pos).min
      max = children.map(&:end_pos).max

      unless beg_pos <= min
        @errors << { type: :min_validation_error, min: min, beg_pos: beg_pos, node: node }
      end

      unless max <= end_pos
        @errors << { type: :max_validation_error, max: max, end_pos: end_pos, node: node }
      end

      p "#{node} => #{children}" if @debug

      children.each do |child|
        p child if @debug
        validate_range0(child)
      end
    end

    def validate_not_cared0(node)
      beg_pos, end_pos = node.beg_pos, node.end_pos
      children = node.children.grep(RubyVM::AST)

      @errors << { type: :first_lineno, node: node } if beg_pos.lineno == 0
      @errors << { type: :first_column, node: node } if beg_pos.column == -1
      @errors << { type: :last_lineno,  node: node } if end_pos.lineno == 0
      @errors << { type: :last_column,  node: node } if end_pos.column == -1

      children.each {|c| validate_not_cared0(c) }
    end
  end

  SRCDIR = File.expand_path("../../..", __FILE__)

  Dir.glob("test/**/*.rb", base: SRCDIR).each do |path|
    define_method("test_ranges:#{path}") do
      helper = Helper.new("#{SRCDIR}/#{path}")
      helper.validate_range

      assert_equal([], helper.errors)
    end
  end

  Dir.glob("test/**/*.rb", base: SRCDIR).each do |path|
    define_method("test_not_cared:#{path}") do
      helper = Helper.new("#{SRCDIR}/#{path}")
      helper.validate_not_cared

      assert_equal([], helper.errors)
    end
  end

  def test_column_with_long_heredoc_identifier
    term = "A"*257
    ast = RubyVM::AST.parse("<<-#{term}\n""ddddddd\n#{term}\n")
    node = ast.children[2]
    assert_equal("NODE_STR", node.type)
    assert_equal(0, node.first_column)
  end

  def test_column_of_heredoc
    node = RubyVM::AST.parse("<<-SRC\nddddddd\nSRC\n").children[2]
    assert_equal("NODE_STR", node.type)
    assert_equal(0, node.first_column)
    assert_equal(6, node.last_column)

    node = RubyVM::AST.parse("<<SRC\nddddddd\nSRC\n").children[2]
    assert_equal("NODE_STR", node.type)
    assert_equal(0, node.first_column)
    assert_equal(5, node.last_column)
  end

  def test_parse_raises_syntax_error
    assert_raise(SyntaxError) { RubyVM::AST.parse("end") }
  end

  def test_parse_file_raises_syntax_error
    Tempfile.create(%w"test_ast .rb") do |f|
      f.puts "end"
      f.close
      path = f.path
      assert_in_out_err(%W[- #{path}], "#{<<-"begin;"}\n#{<<-"end;"}", /keyword_end/, [], success: true)
      begin;
        path = ARGV[0]
        begin
          RubyVM::AST.parse_file(path)
        rescue SyntaxError => e
          puts e.message
        end
      end;
    end
  end

  def test_scope_local_variables
    node = RubyVM::AST.parse("x = 0")
    lv, _, body = *node.children
    assert_equal([:x], lv)
    assert_equal("NODE_LASGN", body.type)
  end

  def test_call
    node = RubyVM::AST.parse("nil.foo")
    _, _, body = *node.children
    assert_equal("NODE_CALL", body.type)
    recv, mid, args = body.children
    assert_equal("NODE_NIL", recv.type)
    assert_equal(:foo, mid)
    assert_nil(args)
  end

  def test_fcall
    node = RubyVM::AST.parse("foo()")
    _, _, body = *node.children
    assert_equal("NODE_FCALL", body.type)
    mid, args = body.children
    assert_equal(:foo, mid)
    assert_nil(args)
  end

  def test_vcall
    node = RubyVM::AST.parse("foo")
    _, _, body = *node.children
    assert_equal("NODE_VCALL", body.type)
    mid, args = body.children
    assert_equal(:foo, mid)
    assert_nil(args)
  end
end
