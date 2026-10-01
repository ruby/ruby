#!/usr/bin/env ruby
require 'open3'
require 'tempfile'
require 'test/unit'

class TestLLDBInit < Test::Unit::TestCase
  def assert_lldb(code, command, pattern, message=nil)
    Tempfile.create('lldb') do |tf|
      tf.puts <<eom
target create ./miniruby
command script import -r misc/lldb_cruby.py
b rb_inspect
run -e'#{code}'
#{command}
eom
      tf.flush
      o, s = Open3.capture2('lldb', '-b', '-s', tf.path)
      assert_true s.success?, message
      assert_match /^\(lldb\) #{Regexp.quote(command)}\n#{pattern}/, o, message
    end
  end

  def assert_rp(expr, pattern, message=nil)
    assert_lldb "p #{expr}", 'rp obj', /(?:bits: \[.*\]\n)?#{pattern}/, message
  end

  def test_rp_object
    assert_rp 'Object.new', 'T_OBJECT'
  end

  def test_rp_regex
    assert_rp '/foo/', '[(]Regex'
  end

  def test_rp_symbol
    assert_rp ':abcde', /T_SYMBOL: \(\h+\)/
  end

  def test_rp_string
    assert_rp '"abc"', /T_STRING: .*\(const char\[\d+\]\) \$\d+ = "abc"/
    assert_rp "\"\u3042\"", /T_STRING: .*\(const char\[\d+\]\) \$\d+ = "\u3042"/
    assert_rp '"' + "\u3042"*10 + '"', /T_STRING: .*\(const char\[\d+\]\) \$\d+ = "#{"\u3042"*10}"/
  end

  def test_rbbt
    assert_lldb 'def foo = p(1); foo', 'rbbt ruby_current_vm_ptr->ractor.main_thread->ec',
                /rb_control_frame_t +TYPE *\n0x\h+ +EVAL +-e <main>\n0x\h+ +METHOD +-e foo\n0x\h+ +CFUNC *\n/
  end
end
