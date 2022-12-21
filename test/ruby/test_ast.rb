# frozen_string_literal: false
require 'test/unit'
require 'tempfile'
require 'pp'

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

    def initialize(path, src: nil)
      @path = path
      @errors = []
      @debug = false
      @ast = RubyVM::AbstractSyntaxTree.parse(src) if src
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
      # These NODE_D* has NODE_LIST as nd_next->nd_next whose last locations
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

  Dir.glob("test/**/*.rb", base: SRCDIR).each do |path|
    define_method("test_all_tokens:#{path}") do
      node = RubyVM::AbstractSyntaxTree.parse_file("#{SRCDIR}/#{path}", keep_tokens: true)
      tokens = node.all_tokens.sort_by { [_1.last[0], _1.last[1]] }
      tokens_bytes = tokens.map { _1[2]}.join.bytes
      source_bytes = File.read("#{SRCDIR}/#{path}").bytes

      assert_equal(source_bytes, tokens_bytes)

      (tokens.count - 1).times do |i|
        token_0 = tokens[i]
        token_1 = tokens[i + 1]
        end_pos = token_0.last[2..3]
        beg_pos = token_1.last[0..1]

        if end_pos[0] == beg_pos[0]
          # When both tokens are same line, column should be consecutives
          assert_equal(beg_pos[1], end_pos[1], "#{token_0}. #{token_1}")
        else
          # Line should be next
          assert_equal(beg_pos[0], end_pos[0] + 1, "#{token_0}. #{token_1}")
          # It should be on the beginning of the line
          assert_equal(0, beg_pos[1], "#{token_0}. #{token_1}")
        end
      end
    end
  end

  private def parse(src)
    EnvUtil.suppress_warning {
      RubyVM::AbstractSyntaxTree.parse(src)
    }
  end

  def test_allocate
    assert_raise(TypeError) {RubyVM::AbstractSyntaxTree::Node.allocate}
  end

  def test_parse_argument_error
    assert_raise(TypeError) {RubyVM::AbstractSyntaxTree.parse(0)}
    assert_raise(TypeError) {RubyVM::AbstractSyntaxTree.parse(nil)}
    assert_raise(TypeError) {RubyVM::AbstractSyntaxTree.parse(false)}
    assert_raise(TypeError) {RubyVM::AbstractSyntaxTree.parse(true)}
    assert_raise(TypeError) {RubyVM::AbstractSyntaxTree.parse(:foo)}
  end

  def test_column_with_long_heredoc_identifier
    term = "A"*257
    ast = parse("<<-#{term}\n""ddddddd\n#{term}\n")
    node = ast.children[2]
    assert_equal(:STR, node.type)
    assert_equal(0, node.first_column)
  end

  def test_column_of_heredoc
    node = parse("<<-SRC\nddddddd\nSRC\n").children[2]
    assert_equal(:STR, node.type)
    assert_equal(0, node.first_column)
    assert_equal(6, node.last_column)

    node = parse("<<SRC\nddddddd\nSRC\n").children[2]
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

  def test_node_id_for_location
    exception = begin
                  raise
                rescue => e
                  e
                end
    loc = exception.backtrace_locations.first
    node_id = RubyVM::AbstractSyntaxTree.node_id_for_backtrace_location(loc)
    node = RubyVM::AbstractSyntaxTree.of(loc, keep_script_lines: true)

    assert_equal node.node_id, node_id
  end

  def test_of_proc_and_method
    proc = Proc.new { 1 + 2 }
    method = self.method(__method__)

    node_proc = RubyVM::AbstractSyntaxTree.of(proc)
    node_method = RubyVM::AbstractSyntaxTree.of(method)

    assert_instance_of(RubyVM::AbstractSyntaxTree::Node, node_proc)
    assert_instance_of(RubyVM::AbstractSyntaxTree::Node, node_method)

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

  def sample_backtrace_location
    [caller_locations(0).first, __LINE__]
  end

  def test_of_backtrace_location
    backtrace_location, lineno = sample_backtrace_location
    node = RubyVM::AbstractSyntaxTree.of(backtrace_location)
    assert_instance_of(RubyVM::AbstractSyntaxTree::Node, node)
    assert_equal(lineno, node.first_lineno)
  end

  def test_of_error
    assert_raise(TypeError) { RubyVM::AbstractSyntaxTree.of("1 + 2") }
  end

  def test_of_proc_and_method_under_eval
    keep_script_lines_back = RubyVM.keep_script_lines
    RubyVM.keep_script_lines = false

    method = self.method(eval("def example_method_#{$$}; end"))
    assert_raise(ArgumentError) { RubyVM::AbstractSyntaxTree.of(method) }

    method = self.method(eval("def self.example_singleton_method_#{$$}; end"))
    assert_raise(ArgumentError) { RubyVM::AbstractSyntaxTree.of(method) }

    method = eval("proc{}")
    assert_raise(ArgumentError) { RubyVM::AbstractSyntaxTree.of(method) }

    method = self.method(eval("singleton_class.define_method(:example_define_method_#{$$}){}"))
    assert_raise(ArgumentError) { RubyVM::AbstractSyntaxTree.of(method) }

    method = self.method(eval("define_singleton_method(:example_dsm_#{$$}){}"))
    assert_raise(ArgumentError) { RubyVM::AbstractSyntaxTree.of(method) }

    method = eval("Class.new{def example_method; end}.instance_method(:example_method)")
    assert_raise(ArgumentError) { RubyVM::AbstractSyntaxTree.of(method) }

    method = eval("Class.new{def example_method; end}.instance_method(:example_method)")
    assert_raise(ArgumentError) { RubyVM::AbstractSyntaxTree.of(method) }

  ensure
    RubyVM.keep_script_lines = keep_script_lines_back
  end

  def test_of_proc_and_method_under_eval_with_keep_script_lines
    pend if ENV['RUBY_ISEQ_DUMP_DEBUG'] # TODO

    keep_script_lines_back = RubyVM.keep_script_lines
    RubyVM.keep_script_lines = true

    method = self.method(eval("def example_method_#{$$}_with_keep_script_lines; end"))
    assert_instance_of(RubyVM::AbstractSyntaxTree::Node, RubyVM::AbstractSyntaxTree.of(method))

    method = self.method(eval("def self.example_singleton_method_#{$$}_with_keep_script_lines; end"))
    assert_instance_of(RubyVM::AbstractSyntaxTree::Node, RubyVM::AbstractSyntaxTree.of(method))

    method = eval("proc{}")
    assert_instance_of(RubyVM::AbstractSyntaxTree::Node, RubyVM::AbstractSyntaxTree.of(method))

    method = self.method(eval("singleton_class.define_method(:example_define_method_#{$$}_with_keep_script_lines){}"))
    assert_instance_of(RubyVM::AbstractSyntaxTree::Node, RubyVM::AbstractSyntaxTree.of(method))

    method = self.method(eval("define_singleton_method(:example_dsm_#{$$}_with_keep_script_lines){}"))
    assert_instance_of(RubyVM::AbstractSyntaxTree::Node, RubyVM::AbstractSyntaxTree.of(method))

    method = eval("Class.new{def example_method_with_keep_script_lines; end}.instance_method(:example_method_with_keep_script_lines)")
    assert_instance_of(RubyVM::AbstractSyntaxTree::Node, RubyVM::AbstractSyntaxTree.of(method))

    method = eval("Class.new{def example_method_with_keep_script_lines; end}.instance_method(:example_method_with_keep_script_lines)")
    assert_instance_of(RubyVM::AbstractSyntaxTree::Node, RubyVM::AbstractSyntaxTree.of(method))

  ensure
    RubyVM.keep_script_lines = keep_script_lines_back
  end

  def test_of_backtrace_location_under_eval
    keep_script_lines_back = RubyVM.keep_script_lines
    RubyVM.keep_script_lines = false

    m = Module.new do
      eval(<<-END, nil, __FILE__, __LINE__)
        def self.sample_backtrace_location
          caller_locations(0).first
        end
      END
    end
    backtrace_location = m.sample_backtrace_location
    assert_raise(ArgumentError) { RubyVM::AbstractSyntaxTree.of(backtrace_location) }

  ensure
    RubyVM.keep_script_lines = keep_script_lines_back
  end

  def test_of_backtrace_location_under_eval_with_keep_script_lines
    pend if ENV['RUBY_ISEQ_DUMP_DEBUG'] # TODO

    keep_script_lines_back = RubyVM.keep_script_lines
    RubyVM.keep_script_lines = true

    m = Module.new do
      eval(<<-END, nil, __FILE__, __LINE__)
        def self.sample_backtrace_location
          caller_locations(0).first
        end
      END
    end
    backtrace_location = m.sample_backtrace_location
    node = RubyVM::AbstractSyntaxTree.of(backtrace_location)
    assert_instance_of(RubyVM::AbstractSyntaxTree::Node, node)
    assert_equal(2, node.first_lineno)

  ensure
    RubyVM.keep_script_lines = keep_script_lines_back
  end

  def test_of_c_method
    c = Class.new { attr_reader :foo }
    assert_nil(RubyVM::AbstractSyntaxTree.of(c.instance_method(:foo)))
  end

  def test_scope_local_variables
    node = RubyVM::AbstractSyntaxTree.parse("_x = 0")
    lv, _, body = *node.children
    assert_equal([:_x], lv)
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
    _, args, = defn.children
    assert_equal(:ARGS, args.type)
  end

  def test_defn_endless
    node = RubyVM::AbstractSyntaxTree.parse("def a = nil")
    _, _, body = *node.children
    assert_equal(:DEFN, body.type)
    mid, defn = body.children
    assert_equal(:a, mid)
    assert_equal(:SCOPE, defn.type)
    _, args, = defn.children
    assert_equal(:ARGS, args.type)
  end

  def test_defs
    node = RubyVM::AbstractSyntaxTree.parse("def a.b; end")
    _, _, body = *node.children
    assert_equal(:DEFS, body.type)
    recv, mid, defn = body.children
    assert_equal(:VCALL, recv.type)
    assert_equal(:b, mid)
    assert_equal(:SCOPE, defn.type)
    _, args, = defn.children
    assert_equal(:ARGS, args.type)
  end

  def test_defs_endless
    node = RubyVM::AbstractSyntaxTree.parse("def a.b = nil")
    _, _, body = *node.children
    assert_equal(:DEFS, body.type)
    recv, mid, defn = body.children
    assert_equal(:VCALL, recv.type)
    assert_equal(:b, mid)
    assert_equal(:SCOPE, defn.type)
    _, args, = defn.children
    assert_equal(:ARGS, args.type)
  end

  def test_dstr
    node = parse('"foo#{1}bar"')
    _, _, body = *node.children
    assert_equal(:DSTR, body.type)
    head, body = body.children
    assert_equal("foo", head)
    assert_equal(:EVSTR, body.type)
    body, = body.children
    assert_equal(:LIT, body.type)
    assert_equal([1], body.children)
  end

  def test_while
    node = RubyVM::AbstractSyntaxTree.parse('1 while qux')
    _, _, body = *node.children
    assert_equal(:WHILE, body.type)
    type1 = body.children[2]
    node = RubyVM::AbstractSyntaxTree.parse('begin 1 end while qux')
    _, _, body = *node.children
    assert_equal(:WHILE, body.type)
    type2 = body.children[2]
    assert_not_equal(type1, type2)
  end

  def test_until
    node = RubyVM::AbstractSyntaxTree.parse('1 until qux')
    _, _, body = *node.children
    assert_equal(:UNTIL, body.type)
    type1 = body.children[2]
    node = RubyVM::AbstractSyntaxTree.parse('begin 1 end until qux')
    _, _, body = *node.children
    assert_equal(:UNTIL, body.type)
    type2 = body.children[2]
    assert_not_equal(type1, type2)
  end

  def test_rest_arg
    rest_arg = lambda do |arg_str|
      node = RubyVM::AbstractSyntaxTree.parse("def a(#{arg_str}) end")
      node = node.children.last.children.last.children[1].children[-4]
    end

    assert_equal(nil, rest_arg.call(''))
    assert_equal(:r, rest_arg.call('*r'))
    assert_equal(:r, rest_arg.call('a, *r'))
    assert_equal(:*, rest_arg.call('*'))
    assert_equal(:*, rest_arg.call('a, *'))
  end

  def test_block_arg
    block_arg = lambda do |arg_str|
      node = RubyVM::AbstractSyntaxTree.parse("def a(#{arg_str}) end")
      node = node.children.last.children.last.children[1].children[-1]
    end

    assert_equal(nil, block_arg.call(''))
    assert_equal(:block, block_arg.call('&block'))
    assert_equal(:&, block_arg.call('&'))
  end

  def test_keyword_rest
    kwrest = lambda do |arg_str|
      node = RubyVM::AbstractSyntaxTree.parse("def a(#{arg_str}) end")
      node = node.children.last.children.last.children[1].children[-2]
      node ? node.children : node
    end

    assert_equal(nil, kwrest.call(''))
    assert_equal([:**], kwrest.call('**'))
    assert_equal(false, kwrest.call('**nil'))
    assert_equal([:a], kwrest.call('**a'))
  end

  def test_argument_forwarding
    forwarding = lambda do |arg_str|
      node = RubyVM::AbstractSyntaxTree.parse("def a(#{arg_str}) end")
      node = node.children.last.children.last.children[1]
      node ? [node.children[-4], node.children[-2]&.children, node.children[-1]] : []
    end

    assert_equal([:*, nil, :&], forwarding.call('...'))
  end

  def test_ranges_numbered_parameter
    helper = Helper.new(__FILE__, src: "1.times {_1}")
    helper.validate_range
    assert_equal([], helper.errors)
  end

  def test_op_asgn2
    node = RubyVM::AbstractSyntaxTree.parse("struct.field += foo")
    _, _, body = *node.children
    assert_equal(:OP_ASGN2, body.type)
    recv, _, mid, op, value = body.children
    assert_equal(:VCALL, recv.type)
    assert_equal(:field, mid)
    assert_equal(:+, op)
    assert_equal(:VCALL, value.type)
  end

  def test_args
    rest = 6
    node = RubyVM::AbstractSyntaxTree.parse("proc { |a| }")
    _, args = *node.children.last.children[1].children
    assert_equal(nil, args.children[rest])

    node = RubyVM::AbstractSyntaxTree.parse("proc { |a,| }")
    _, args = *node.children.last.children[1].children
    assert_equal(:NODE_SPECIAL_EXCESSIVE_COMMA, args.children[rest])

    node = RubyVM::AbstractSyntaxTree.parse("proc { |*a| }")
    _, args = *node.children.last.children[1].children
    assert_equal(:a, args.children[rest])
  end

  def test_keep_script_lines_for_parse
    node = RubyVM::AbstractSyntaxTree.parse(<<~END, keep_script_lines: true)
1.times do
  2.times do
  end
end
__END__
dummy
    END

    expected = [
      "1.times do\n",
      "  2.times do\n",
      "  end\n",
      "end\n",
      "__END__\n",
    ]
    assert_equal(expected, node.script_lines)

    expected =
      "1.times do\n" +
      "  2.times do\n" +
      "  end\n" +
      "end"
    assert_equal(expected, node.source)

    expected =
             "do\n" +
      "  2.times do\n" +
      "  end\n" +
      "end"
    assert_equal(expected, node.children.last.children.last.source)

    expected =
        "2.times do\n" +
      "  end"
    assert_equal(expected, node.children.last.children.last.children.last.source)
  end

  def test_keep_script_lines_for_of
    proc = Proc.new { 1 + 2 }
    method = self.method(__method__)

    node_proc = RubyVM::AbstractSyntaxTree.of(proc, keep_script_lines: true)
    node_method = RubyVM::AbstractSyntaxTree.of(method, keep_script_lines: true)

    assert_equal("{ 1 + 2 }", node_proc.source)
    assert_equal("def test_keep_script_lines_for_of\n", node_method.source.lines.first)
  end

  def test_encoding_with_keep_script_lines
    # Stop a warning "possibly useless use of a literal in void context"
    verbose_bak, $VERBOSE = $VERBOSE, nil

    enc = Encoding::EUC_JP
    code = "__ENCODING__".encode(enc)

    assert_equal(enc, eval(code))

    node = RubyVM::AbstractSyntaxTree.parse(code, keep_script_lines: false)
    assert_equal(enc, node.children[2].children[0])

    node = RubyVM::AbstractSyntaxTree.parse(code, keep_script_lines: true)
    assert_equal(enc, node.children[2].children[0])

  ensure
    $VERBOSE = verbose_bak
  end

  def test_e_option
    assert_in_out_err(["-e", "def foo; end; pp RubyVM::AbstractSyntaxTree.of(method(:foo)).type"],
                      "", [":SCOPE"], [])
  end

  def test_error_tolerant
    verbose_bak, $VERBOSE = $VERBOSE, false
    node = RubyVM::AbstractSyntaxTree.parse(<<~STR, error_tolerant: true)
      class A
        def m
          if;
          a = 10
        end
      end
    STR
    assert_nil($!)

    assert_equal(:SCOPE, node.type)
  ensure
    $VERBOSE = verbose_bak
  end

  def test_error_tolerant_end_is_short_for_method_define
    assert_error_tolerant(<<~STR, <<~EXP)
      def m
        m2
    STR
      (SCOPE@1:0-2:4
       tbl: []
       args: nil
       body:
         (DEFN@1:0-2:4
          mid: :m
          body:
            (SCOPE@1:0-2:4
             tbl: []
             args:
               (ARGS@1:5-1:5
                pre_num: 0
                pre_init: nil
                opt: nil
                first_post: nil
                post_num: 0
                post_init: nil
                rest: nil
                kw: nil
                kwrest: nil
                block: nil)
             body: (VCALL@2:2-2:4 :m2))))
    EXP
  end

  def test_error_tolerant_end_is_short_for_singleton_method_define
    assert_error_tolerant(<<~STR, <<~EXP)
      def obj.m
        m2
    STR
      (SCOPE@1:0-2:4
       tbl: []
       args: nil
       body:
         (DEFS@1:0-2:4 (VCALL@1:4-1:7 :obj) :m
            (SCOPE@1:0-2:4
             tbl: []
             args:
               (ARGS@1:9-1:9
                pre_num: 0
                pre_init: nil
                opt: nil
                first_post: nil
                post_num: 0
                post_init: nil
                rest: nil
                kw: nil
                kwrest: nil
                block: nil)
             body: (VCALL@2:2-2:4 :m2))))
    EXP
  end

  def test_error_tolerant_end_is_short_for_begin
    assert_error_tolerant(<<~STR, <<~EXP)
      begin
        a = 1
    STR
      (SCOPE@1:0-2:7 tbl: [:a] args: nil body: (LASGN@2:2-2:7 :a (LIT@2:6-2:7 1)))
    EXP
  end

  def test_error_tolerant_end_is_short_for_if
    assert_error_tolerant(<<~STR, <<~EXP)
      if cond
        a = 1
    STR
      (SCOPE@1:0-2:7
       tbl: [:a]
       args: nil
       body:
         (IF@1:0-2:7 (VCALL@1:3-1:7 :cond) (LASGN@2:2-2:7 :a (LIT@2:6-2:7 1)) nil))
    EXP

    assert_error_tolerant(<<~STR, <<~EXP)
      if cond
        a = 1
      else
    STR
      (SCOPE@1:0-3:4
       tbl: [:a]
       args: nil
       body:
         (IF@1:0-3:4 (VCALL@1:3-1:7 :cond) (LASGN@2:2-2:7 :a (LIT@2:6-2:7 1))
            (BEGIN@3:4-3:4 nil)))
    EXP
  end

  def test_error_tolerant_end_is_short_for_unless
    assert_error_tolerant(<<~STR, <<~EXP)
      unless cond
        a = 1
    STR
      (SCOPE@1:0-2:7
       tbl: [:a]
       args: nil
       body:
         (UNLESS@1:0-2:7 (VCALL@1:7-1:11 :cond) (LASGN@2:2-2:7 :a (LIT@2:6-2:7 1))
            nil))
    EXP

    assert_error_tolerant(<<~STR, <<~EXP)
      unless cond
        a = 1
      else
    STR
      (SCOPE@1:0-3:4
       tbl: [:a]
       args: nil
       body:
         (UNLESS@1:0-3:4 (VCALL@1:7-1:11 :cond) (LASGN@2:2-2:7 :a (LIT@2:6-2:7 1))
            (BEGIN@3:4-3:4 nil)))
    EXP
  end

  def test_error_tolerant_end_is_short_for_while
    assert_error_tolerant(<<~STR, <<~EXP)
      while true
        m
    STR
      (SCOPE@1:0-2:3
       tbl: []
       args: nil
       body: (WHILE@1:0-2:3 (TRUE@1:6-1:10) (VCALL@2:2-2:3 :m) true))
    EXP
  end

  def test_error_tolerant_end_is_short_for_until
    assert_error_tolerant(<<~STR, <<~EXP)
      until true
        m
    STR
      (SCOPE@1:0-2:3
       tbl: []
       args: nil
       body: (UNTIL@1:0-2:3 (TRUE@1:6-1:10) (VCALL@2:2-2:3 :m) true))
    EXP
  end

  def test_error_tolerant_end_is_short_for_case
    assert_error_tolerant(<<~STR, <<~EXP)
      case a
      when 1
    STR
      (SCOPE@1:0-2:6
       tbl: []
       args: nil
       body:
         (CASE@1:0-2:6 (VCALL@1:5-1:6 :a)
            (WHEN@2:0-2:6 (LIST@2:5-2:6 (LIT@2:5-2:6 1) nil) (BEGIN@2:6-2:6 nil)
               nil)))
    EXP


    assert_error_tolerant(<<~STR, <<~EXP)
      case
      when a == 1
    STR
      (SCOPE@1:0-2:11
       tbl: []
       args: nil
       body:
         (CASE2@1:0-2:11 nil
            (WHEN@2:0-2:11
               (LIST@2:5-2:11
                  (OPCALL@2:5-2:11 (VCALL@2:5-2:6 :a) :==
                     (LIST@2:10-2:11 (LIT@2:10-2:11 1) nil)) nil)
               (BEGIN@2:11-2:11 nil) nil)))
    EXP


    assert_error_tolerant(<<~STR, <<~EXP)
      case a
      in {a: String}
    STR
      (SCOPE@1:0-2:14
       tbl: []
       args: nil
       body:
         (CASE3@1:0-2:14 (VCALL@1:5-1:6 :a)
            (IN@2:0-2:14
               (HSHPTN@2:4-2:13
                const: nil
                kw:
                  (HASH@2:4-2:13
                     (LIST@2:4-2:13 (LIT@2:4-2:6 :a) (CONST@2:7-2:13 :String) nil))
                kwrest: nil) (BEGIN@2:14-2:14 nil) nil)))
    EXP
  end

  def test_error_tolerant_end_is_short_for_for
    assert_error_tolerant(<<~STR, <<~EXP)
      for i in ary
        m
    STR
      (SCOPE@1:0-2:3
       tbl: [:i]
       args: nil
       body:
         (FOR@1:0-2:3 (VCALL@1:9-1:12 :ary)
            (SCOPE@1:0-2:3
             tbl: [nil]
             args:
               (ARGS@1:4-1:5
                pre_num: 1
                pre_init: (LASGN@1:4-1:5 :i (DVAR@1:4-1:5 nil))
                opt: nil
                first_post: nil
                post_num: 0
                post_init: nil
                rest: nil
                kw: nil
                kwrest: nil
                block: nil)
             body: (VCALL@2:2-2:3 :m))))
    EXP
  end

  def test_error_tolerant_end_is_short_for_class
    assert_error_tolerant(<<~STR, <<~EXP)
      class C
    STR
      (SCOPE@1:0-1:7
       tbl: []
       args: nil
       body:
         (CLASS@1:0-1:7 (COLON2@1:6-1:7 nil :C) nil
            (SCOPE@1:0-1:7 tbl: [] args: nil body: (BEGIN@1:7-1:7 nil))))
    EXP
  end

  def test_error_tolerant_end_is_short_for_module
    assert_error_tolerant(<<~STR, <<~EXP)
      module M
    STR
      (SCOPE@1:0-1:8
       tbl: []
       args: nil
       body:
         (MODULE@1:0-1:8 (COLON2@1:7-1:8 nil :M)
            (SCOPE@1:0-1:8 tbl: [] args: nil body: (BEGIN@1:8-1:8 nil))))
    EXP
  end

  def test_error_tolerant_end_is_short_for_do
    assert_error_tolerant(<<~STR, <<~EXP)
      m do
        a
    STR
      (SCOPE@1:0-2:3
       tbl: []
       args: nil
       body:
         (ITER@1:0-2:3 (FCALL@1:0-1:1 :m nil)
            (SCOPE@1:2-2:3 tbl: [] args: nil body: (VCALL@2:2-2:3 :a))))
    EXP
  end

  def test_error_tolerant_end_is_short_for_do_block
    assert_error_tolerant(<<~STR, <<~EXP)
      m 1 do
        a
    STR
      (SCOPE@1:0-2:3
       tbl: []
       args: nil
       body:
         (ITER@1:0-2:3 (FCALL@1:0-1:3 :m (LIST@1:2-1:3 (LIT@1:2-1:3 1) nil))
            (SCOPE@1:4-2:3 tbl: [] args: nil body: (VCALL@2:2-2:3 :a))))
    EXP
  end

  def test_error_tolerant_end_is_short_for_do_LAMBDA
    assert_error_tolerant(<<~STR, <<~EXP)
      -> do
        a
    STR
      (SCOPE@1:0-2:3
       tbl: []
       args: nil
       body:
         (LAMBDA@1:0-2:3
            (SCOPE@1:2-2:3
             tbl: []
             args:
               (ARGS@1:2-1:2
                pre_num: 0
                pre_init: nil
                opt: nil
                first_post: nil
                post_num: 0
                post_init: nil
                rest: nil
                kw: nil
                kwrest: nil
                block: nil)
             body: (VCALL@2:2-2:3 :a))))
    EXP
  end

  def test_error_tolerant_treat_end_as_keyword_based_on_indent
    assert_error_tolerant(<<~STR, <<~EXP)
      module Z
        class Foo
          foo.
        end

        def bar
        end
      end
    STR
      (SCOPE@1:0-8:3
       tbl: []
       args: nil
       body:
         (MODULE@1:0-8:3 (COLON2@1:7-1:8 nil :Z)
            (SCOPE@1:0-8:3
             tbl: []
             args: nil
             body:
               (BLOCK@1:8-7:5 (BEGIN@1:8-1:8 nil)
                  (CLASS@2:2-4:5 (COLON2@2:8-2:11 nil :Foo) nil
                     (SCOPE@2:2-4:5
                      tbl: []
                      args: nil
                      body: (BLOCK@2:11-4:5 (BEGIN@2:11-2:11 nil) (ERROR@3:4-4:5))))
                  (DEFN@6:2-7:5
                   mid: :bar
                   body:
                     (SCOPE@6:2-7:5
                      tbl: []
                      args:
                        (ARGS@6:9-6:9
                         pre_num: 0
                         pre_init: nil
                         opt: nil
                         first_post: nil
                         post_num: 0
                         post_init: nil
                         rest: nil
                         kw: nil
                         kwrest: nil
                         block: nil)
                      body: nil))))))
    EXP
  end

  def test_error_tolerant_expr_value_can_be_error
    assert_error_tolerant(<<~STR, <<~EXP)
      def m
        if
      end
    STR
      (SCOPE@1:0-3:3
       tbl: []
       args: nil
       body:
         (DEFN@1:0-3:3
          mid: :m
          body:
            (SCOPE@1:0-3:3
             tbl: []
             args:
               (ARGS@1:5-1:5
                pre_num: 0
                pre_init: nil
                opt: nil
                first_post: nil
                post_num: 0
                post_init: nil
                rest: nil
                kw: nil
                kwrest: nil
                block: nil)
             body: (IF@2:2-3:3 (ERROR@3:0-3:3) nil nil))))
    EXP
  end

  def assert_error_tolerant(src, expected)
    begin
      verbose_bak, $VERBOSE = $VERBOSE, false
      node = RubyVM::AbstractSyntaxTree.parse(src, error_tolerant: true)
    ensure
      $VERBOSE = verbose_bak
    end
    assert_nil($!)
    str = ""
    PP.pp(node, str, 80)
    assert_equal(expected, str)
  end
end
