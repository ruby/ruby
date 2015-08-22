# coding: US-ASCII
require 'test/unit'
require 'stringio'

require 'tmpdir'
require 'tempfile'

class TestMagicLine < Test::Unit::TestCase
  def setup
    @verbose = $VERBOSE
    $VERBOSE = nil
  end

  def teardown
    $VERBOSE = @verbose
  end

  def test_unused_variable_with_line
    o = Object.new
    assert_warning(/assigned but unused variable/) {o.instance_eval("def foo; a=1; nil; end")}
    a = "\u{3042}"
    assert_warning(/:100:/) {
      o.instance_eval("# -*- line: 100 -*-\ndef foo; #{a}=1; nil; end")
    }
  end

  def test_unused_variable_with_line_file
    o = Object.new
    assert_warning(/assigned but unused variable/) {o.instance_eval("def foo; a=1; nil; end")}
    a = "\u{3042}"
    assert_warning(/bob:100:/) {
      o.instance_eval("# -*- line: bob 100 -*-\ndef foo; #{a}=1; nil; end")
    }
  end

  def test_line_exception_out
    Tempfile.create(["test_ruby_test_magicline", ".rb"]) {|t|
      err = ["bob.rb:100:in `<main>': Error: bob.rb:100: (RuntimeError)"]
      t.puts "# -*- line: bob.rb 100 -*-"
      t.puts "raise 'Error: bob.rb:100:'"
      t.flush
      assert_in_out_err(["-w", t.path], "", [], err, '[ruby-core:25442]')
    }
  end

  def test_thread_backtrace_location
    eval <<-'EOF', nil, __FILE__, __LINE__
      # -*- line: bob.rb 100 -*-
      l = caller_locations(0)[0];
      assert_equal('bob.rb', l.path);
      assert_equal(100, l.lineno);
    EOF
  end

  def test_trace_string
      eval <<-'EOF', nil, __FILE__, __LINE__
begin
  $x = 1
  trace_var :$x, "# -*- line: trace 1 -*-
$y = :bar; raise 'HI'"
  $x = 42
rescue => error
  assert_equal("trace:1:in `test_trace_string'", error.backtrace_locations[0].to_s);
ensure
  untrace_var :$x
end
    EOF
  end

end
