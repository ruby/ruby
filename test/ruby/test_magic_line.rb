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
    assert_warning(/\(eval\):1:/) {o.instance_eval("def foo; a=1; nil; end")}
    o = Object.new
    assert_warning(/bob:100:/) {
      o.instance_eval("# -*- line: bob 100 -*-\ndef foo; a=1; nil; end")
    }
  end

  def test_compile_error_line_eof
    o = Object.new
    out, err = capture_io do
       begin
         o.instance_eval("# -*- line: test.rb 100 -*-\ndef foo; a=<<EOF; end")
       rescue Exception => error
         assert_match(/^test.rb:100: syntax error/, error.message);
       else
         assert(false, 'no exception');
       end
    end
  end

  def test_compile_error_line
    o = Object.new
    out, err = capture_io do
       begin
         o.instance_eval("def foo; a=1 nil; end")
       rescue Exception => error
         assert_match(/^.eval.:1: syntax error/, error.message);
       else
         assert(false, 'no exception');
       end
    end
    o = Object.new
    out, err = capture_io do
       begin
         o.instance_eval("# -*- line: 100 -*-\ndef foo; a=1 nil; end")
       rescue Exception => error
         assert_match("(eval):100: syntax error", error.message);
       else
         assert(false, 'no exception');
       end
    end
    o = Object.new
    out, err = capture_io do
       begin
         o.instance_eval("# -*- line: joe.rb 100 -*-\ndef foo; a=1 nil; end")
       rescue Exception => error
         assert_match("joe.rb:100: syntax error", error.message);
       else
         assert(false, 'no exception');
       end
    end
  end

  def test_line_exception_out
    Tempfile.create(["test_ruby_test_magicline", ".rb"]) {|t|
      t.puts "# "
      t.puts "# "
      t.puts "raise 'Error: #{t.path}:100:'"
      t.flush
      err = ["#{t.path}:3:in `<main>': Error: #{t.path}:100: (RuntimeError)"]
      assert_in_out_err(["-w", t.path], "", [], err)

      t.rewind
      t.puts "# -*- line: bob.rb 100 -*-"
      t.puts "raise 'Error: bob.rb:100:'"
      t.puts "__END__"
      t.flush
      err = ["bob.rb:100:in `<main>': Error: bob.rb:100: (RuntimeError)"]
      assert_in_out_err(["-w", t.path], "", [], err)

      t.rewind
      t.puts "# -*- line: bill.rb 100 -*-"
      t.puts "# empty line"
      t.puts "raise 'Error: bill.rb:101:'"
      t.puts "__END__"
      t.flush
      err = ["bill.rb:101:in `<main>': Error: bill.rb:101: (RuntimeError)"]
      assert_in_out_err(["-w", t.path], "", [], err)
    }
  end

  def test_line_warning_out
    Tempfile.create(["test_ruby_test_magicline", ".rb"]) {|t|
      t.rewind
      t.puts "# -*- line: bill.rb 100 -*-"
      t.puts "def foo; a=1; nil; end"
      t.puts "__END__"
      t.flush
      err = ["bill.rb:100: warning: assigned but unused variable - a"]
      assert_in_out_err(["-w", t.path], "", [], err)

      t.rewind
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

  # test message from parser_set_compile_option_flag
  def test_frozen_string_literal
    Tempfile.create(["test_ruby_test_rubyoption", ".rb"]) {|t|
      t.puts "# "
      t.puts "# -*- frozen-string-literal: notbool -*-"
      t.puts "__END__"
      t.flush
      err = ["#{t.path}:2: warning: invalid value for frozen_string_literal: notbool"]
      assert_in_out_err(["-w", t.path], "", [], err)
      assert_in_out_err(["-wr", t.path, "-e", ""], "", [], err)

      t.rewind
      t.puts "# -*- line: 100 -*-"
      t.puts "# -*- frozen-string-literal: notbool -*-"
      t.puts "__END__"
      t.flush
      err = ["#{t.path}:100: warning: invalid value for frozen_string_literal: notbool"]
      assert_in_out_err(["-w", t.path], "", [], err)
      assert_in_out_err(["-wr", t.path, "-e", ""], "", [], err)

      t.rewind
      t.puts "# -*- line: annette 100 -*-"
      t.puts "# -*- frozen-string-literal: notbool -*-"
      t.puts "__END__"
      t.flush
      err = ["annette:100: warning: invalid value for frozen_string_literal: notbool"]
      assert_in_out_err(["-w", t.path], "", [], err)
      assert_in_out_err(["-wr", t.path, "-e", ""], "", [], err)
    }
  end

  # test parser_set_token_info
  def test_indentation_check
    Tempfile.create(["test_ruby_test_rubyoption", ".rb"]) {|t|
      t.puts "# "
      t.puts "# -*- warn-indent: bill -*-"
      t.puts "begin"
      t.puts "end"
      t.puts "__END__"
      t.flush
      err = ["#{t.path}:2: warning: invalid value for warn_indent: bill"]
      assert_in_out_err(["-w", t.path], "", [], err)
      assert_in_out_err(["-wr", t.path, "-e", ""], "", [], err)

      t.rewind
      t.puts "# -*- line: 100 -*-"
      t.puts "# -*- warn-indent: bill -*-"
      t.puts "begin"
      t.puts "end"
      t.puts "__END__"
      t.flush
      err = ["#{t.path}:100: warning: invalid value for warn_indent: bill"]
      assert_in_out_err(["-w", t.path], "", [], err)
      assert_in_out_err(["-wr", t.path, "-e", ""], "", [], err)

      t.rewind
      t.puts "# -*- line: annette 100 -*-"
      t.puts "# -*- warn-indent: bill -*-"
      t.puts "begin"
      t.puts "end"
      t.puts "__END__"
      t.flush
      err = ["annette:100: warning: invalid value for warn_indent: bill"]
      assert_in_out_err(["-w", t.path], "", [], err)
      assert_in_out_err(["-wr", t.path, "-e", ""], "", [], err)
    }
  end

end
