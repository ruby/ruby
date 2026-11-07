# frozen_string_literal: false
require 'test/unit'
require_relative '../lib/parser_support'

class TestRubyVM < Test::Unit::TestCase
  def test_stat
    assert_kind_of Hash, RubyVM.stat

    RubyVM.stat(stat = {})
    assert_not_empty stat
  end

  def test_stat_unknown
    assert_raise(ArgumentError){ RubyVM.stat(:unknown) }
    assert_raise_with_message(ArgumentError, /\u{30eb 30d3 30fc}/) {RubyVM.stat(:"\u{30eb 30d3 30fc}")}
  end

  def test_disable_shape_redblack_cache
    code = "#{<<~"begin;"}\n#{<<~'end;'}"
    begin;
      obj = Object.new
      20.times { |i| obj.instance_variable_set(:"@a#{i}", i) }
      assert_equal 19, obj.instance_variable_get(:@a19)
    end;

    assert_separately([], code + "assert_operator RubyVM.stat(:shape_cache_size), :>, 0")
    assert_separately([{"RUBY_SHAPE_REDBLACK_CACHE" => "disable"}], code + "assert_equal 0, RubyVM.stat(:shape_cache_size)")
  end if RUBY_PLATFORM.include?("linux")

  def parse_and_compile
    script = <<~RUBY
      _a = 1
      def foo
        _b = 2
      end
      1.times{
        _c = 3
      }
    RUBY

    ast = RubyVM::AbstractSyntaxTree.parse(script)
    iseq = RubyVM::InstructionSequence.compile(script)

    [ast, iseq]
  end

  def test_keep_script_lines
    omit if ParserSupport.prism_enabled?
    pend if ENV['RUBY_ISEQ_DUMP_DEBUG'] # TODO

    prev_conf = RubyVM.keep_script_lines

    # keep
    RubyVM.keep_script_lines = true

    ast, iseq = *parse_and_compile

    lines = ast.script_lines
    assert_equal Array, lines.class

    lines = iseq.script_lines
    assert_equal Array, lines.class
    iseq.each_child{|child|
      assert_equal lines, child.script_lines
    }
    assert lines.frozen?

    # don't keep
    RubyVM.keep_script_lines = false

    ast, iseq = *parse_and_compile

    lines = ast.script_lines
    assert_equal nil, lines

    lines = iseq.script_lines
    assert_equal nil, lines
    iseq.each_child{|child|
      assert_equal lines, child.script_lines
    }

  ensure
    RubyVM.keep_script_lines = prev_conf
  end
end
