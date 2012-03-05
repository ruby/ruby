require 'test/unit'

class TestSyntax < Test::Unit::TestCase
  def assert_valid_syntax(code, fname, mesg = fname)
    code = code.dup.force_encoding("ascii-8bit")
    code.sub!(/\A(?:\xef\xbb\xbf)?(\s*\#.*$)*(\n)?/n) {
      "#$&#{"\n" if $1 && !$2}BEGIN{throw tag, :ok}\n"
    }
    code.force_encoding("us-ascii")
    verbose, $VERBOSE = $VERBOSE, nil
    assert_nothing_raised(SyntaxError, mesg) do
      assert_equal(:ok, catch {|tag| eval(code, binding, fname, 0)}, mesg)
    end
  ensure
    $VERBOSE = verbose
  end

  def test_syntax
    assert_nothing_raised(Exception) do
      for script in Dir[File.expand_path("../../../{lib,sample,ext,test}/**/*.rb", __FILE__)].sort
        assert_valid_syntax(IO::read(script), script)
      end
    end
  end

  def test_must_ascii_compatible
    require 'tempfile'
    f = Tempfile.new("must_ac_")
    Encoding.list.each do |enc|
      next unless enc.ascii_compatible?
      make_tmpsrc(f, "# -*- coding: #{enc.name} -*-")
      assert_nothing_raised(ArgumentError, enc.name) {load(f.path)}
    end
    Encoding.list.each do |enc|
      next if enc.ascii_compatible?
      make_tmpsrc(f, "# -*- coding: #{enc.name} -*-")
      assert_raise(ArgumentError, enc.name) {load(f.path)}
    end
    f.close!
  end

  def test_script_lines
    require 'tempfile'
    f = Tempfile.new("bug4361_")
    bug4361 = '[ruby-dev:43168]'
    with_script_lines do |debug_lines|
      Encoding.list.each do |enc|
        next unless enc.ascii_compatible?
        make_tmpsrc(f, "# -*- coding: #{enc.name} -*-\n#----------------")
        load(f.path)
        assert_equal([f.path], debug_lines.keys)
        assert_equal([enc, enc], debug_lines[f.path].map(&:encoding), bug4361)
      end
    end
    f.close!
  end

  def test_newline_in_block_parameters
    bug = '[ruby-dev:45292]'
    ["", "a", "a, b"].product(["", ";x", [";", "x"]]) do |params|
      params = ["|", *params, "|"].join("\n")
      assert_valid_syntax("1.times{#{params}}", __FILE__, "#{bug} #{params.inspect}")
    end
  end
  
  def test_do_block_after_do_block_without_parenthesis
    assert_nothing_raised(SyntaxError) { eval(<<-CODE) }
        ["elem"].each_with_object [] do
        end.map do
        end
    CODE
  end
  
  def test_do_block_after_do_block_without_parenthesis2
    assert_nothing_raised(SyntaxError) { eval(<<-CODE) }
        ["elem"].each_with_object [] do
        end.each_with_object [] do
        end
    CODE
  end
  
  def test_brace_block_after_do_block_without_parenthesis
    assert_nothing_raised(SyntaxError) { eval(<<-CODE) }
        ["elem"].each_with_object [] do
        end.map {
        }
    CODE
  end

  def test_brace_block_after_do_block_without_parenthesis2
    assert_nothing_raised(SyntaxError) { eval(<<-CODE) }
        ["elem"].each_with_object [] do
        end.each_with_object([]) {
        }
    CODE
  end

  private

  def make_tmpsrc(f, src)
    f.open
    f.truncate(0)
    f.puts(src)
    f.close
  end

  def with_script_lines
    script_lines = nil
    debug_lines = {}
    Object.class_eval do
      if defined?(SCRIPT_LINES__)
        script_lines = SCRIPT_LINES__
        remove_const :SCRIPT_LINES__
      end
      const_set(:SCRIPT_LINES__, debug_lines)
    end
    yield debug_lines
  ensure
    Object.class_eval do
      remove_const :SCRIPT_LINES__
      const_set(:SCRIPT_LINES__, script_lines) if script_lines
    end
  end
end
