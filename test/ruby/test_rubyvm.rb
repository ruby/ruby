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

  def test_shape_redblack_cache_size
    code = "#{<<~"begin;"}\n#{<<~'end;'}"
    begin;
      obj = Object.new
      20.times { |i| obj.instance_variable_set(:"@a#{i}", i) }
      raise unless obj.instance_variable_get(:@a19) == 19
      p RubyVM.stat(:shape_cache_size)
    end;
    env = "RUBY_SHAPE_REDBLACK_CACHE_SIZE"

    default = nil
    assert_in_out_err([{env => nil}], code, [], []) do |out, _|
      default = out
      assert_operator Integer(out.first), :>, 50
    end

    # Valid values
    assert_in_out_err([{env => "0"}], code, ["0"], [])
    assert_in_out_err([{env => "50"}], code, ["49"], [])
    assert_in_out_err([{env => "0x32"}], code, ["49"], [])
    assert_in_out_err([{env => "50 "}], code, ["49"], [])

    # Ignored values
    assert_in_out_err([{env => ""}], code, default, [])
    assert_in_out_err([{env => "50x"}], code, default,
                      ["invalid string for #{env}: 50x"])
    assert_in_out_err([{env => "-1"}], code, default,
                      ["#{env}=-1 (default value: 16777216) is ignored because it must be between 0 and 134217728."])
    assert_in_out_err([{env => "134217729"}], code, default,
                      ["#{env}=134217729 (default value: 16777216) is ignored because it must be between 0 and 134217728."])
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
