# frozen_string_literal: false
require 'test/unit'
require 'tempfile'

class RubyVM
  module AbstractSyntaxTree
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
      @ast = RubyVM::AbstractSyntaxTree.parse_file(@path)
    end

    private

    def validate_range0(node)
      beg_pos, end_pos = node.beg_pos, node.end_pos
      children = node.children.grep(RubyVM::AbstractSyntaxTree::Node)

      return true if children.empty?
      # These NODE_D* has NODE_ARRAY as nd_next->nd_next whose last locations
      # we can not update when item is appended.
      return true if [:DSTR, :DXSTR, :DREGX, :DSYM].include? node.type

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
      children = node.children.grep(RubyVM::AbstractSyntaxTree::Node)

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

  def test_allocate
    assert_raise(TypeError) {RubyVM::AbstractSyntaxTree::Node.allocate}
  end

  def test_column_with_long_heredoc_identifier
    term = "A"*257
    ast = RubyVM::AbstractSyntaxTree.parse("<<-#{term}\n""ddddddd\n#{term}\n")
    node = ast.children[2]
    assert_equal(:STR, node.type)
    assert_equal(0, node.first_column)
  end

  def test_column_of_heredoc
    node = RubyVM::AbstractSyntaxTree.parse("<<-SRC\nddddddd\nSRC\n").children[2]
    assert_equal(:STR, node.type)
    assert_equal(0, node.first_column)
    assert_equal(6, node.last_column)

    node = RubyVM::AbstractSyntaxTree.parse("<<SRC\nddddddd\nSRC\n").children[2]
    assert_equal(:STR, node.type)
    assert_equal(0, node.first_column)
    assert_equal(5, node.last_column)
  end

  def test_parse_raises_syntax_error
    assert_raise_with_message(SyntaxError, /\bend\b/) do
      RubyVM::AbstractSyntaxTree.parse("end")
    end
  end

  def test_parse_file_raises_syntax_error
    Tempfile.create(%w"test_ast .rb") do |f|
      f.puts "end"
      f.close
      assert_raise_with_message(SyntaxError, /\bend\b/) do
        RubyVM::AbstractSyntaxTree.parse_file(f.path)
      end
    end
  end

  def test_of
    proc = Proc.new { 1 + 2 }
    method = self.method(__method__)

    node_proc = RubyVM::AbstractSyntaxTree.of(proc)
    node_method = RubyVM::AbstractSyntaxTree.of(method)

    assert_instance_of(RubyVM::AbstractSyntaxTree::Node, node_proc)
    assert_instance_of(RubyVM::AbstractSyntaxTree::Node, node_method)
    assert_raise(TypeError) { RubyVM::AbstractSyntaxTree.of("1 + 2") }

    Tempfile.create(%w"test_of .rb") do |tmp|
      tmp.print "#{<<-"begin;"}\n#{<<-'end;'}"
      begin;
        SCRIPT_LINES__ = {}
        assert_instance_of(RubyVM::AbstractSyntaxTree::Node, RubyVM::AbstractSyntaxTree.of(proc {|x| x}))
      end;
      tmp.close
      assert_separately(["-", tmp.path], "#{<<~"begin;"}\n#{<<~'end;'}")
      begin;
        load ARGV[0]
        assert_empty(SCRIPT_LINES__)
      end;
    end
  end

  def test_scope_local_variables
    node = RubyVM::AbstractSyntaxTree.parse("x = 0")
    lv, _, body = *node.children
    assert_equal([:x], lv)
    assert_equal(:LASGN, body.type)
  end

  def test_call
    node = RubyVM::AbstractSyntaxTree.parse("nil.foo")
    _, _, body = *node.children
    assert_equal(:CALL, body.type)
    recv, mid, args = body.children
    assert_equal(:NIL, recv.type)
    assert_equal(:foo, mid)
    assert_nil(args)
  end

  def test_fcall
    node = RubyVM::AbstractSyntaxTree.parse("foo()")
    _, _, body = *node.children
    assert_equal(:FCALL, body.type)
    mid, args = body.children
    assert_equal(:foo, mid)
    assert_nil(args)
  end

  def test_vcall
    node = RubyVM::AbstractSyntaxTree.parse("foo")
    _, _, body = *node.children
    assert_equal(:VCALL, body.type)
    mid, args = body.children
    assert_equal(:foo, mid)
    assert_nil(args)
  end

  def test_defn
    node = RubyVM::AbstractSyntaxTree.parse("def a; end")
    _, _, body = *node.children
    assert_equal(:DEFN, body.type)
    mid, defn = body.children
    assert_equal(:a, mid)
    assert_equal(:SCOPE, defn.type)
  end

  def test_defs
    node = RubyVM::AbstractSyntaxTree.parse("def a.b; end")
    _, _, body = *node.children
    assert_equal(:DEFS, body.type)
    recv, mid, defn = body.children
    assert_equal(:VCALL, recv.type)
    assert_equal(:b, mid)
    assert_equal(:SCOPE, defn.type)
  end
end
