begin
  require "readline"
rescue LoadError
end

if defined?(Readline)

require "test/unit"
require "tempfile"

class TestReadline < Test::Unit::TestCase
  def test_readline
    stdin = Tempfile.new("test_readline_stdin")
    stdout = Tempfile.new("test_readline_stdout")
    begin
      stdin.write("hello\n")
      stdin.rewind
      line = replace_stdio(stdin, stdout) { Readline.readline("> ") }
      assert_equal("hello", line)
      assert_equal(true, line.tainted?)
      assert_raises(SecurityError) do
        Thread.start {
          $SAFE = 1
          replace_stdio(stdin, stdout) { Readline.readline("> ".taint) }
        }.join
      end
      assert_raises(SecurityError) do
        Thread.start {
          $SAFE = 4
          replace_stdio(stdin, stdout) { Readline.readline("> ") }
        }.join
      end
      stdout.rewind
      assert_equal("> ", stdout.read(2))
    ensure
      stdin.close(true)
      stdout.close(true)
    end
  end

  def test_completion_append_character
    Readline.completion_append_character = nil
    assert_equal(nil, Readline.completion_append_character)
    Readline.completion_append_character = "x"
    assert_equal("x", Readline.completion_append_character)
    Readline.completion_append_character = "xyz"
    assert_equal("x", Readline.completion_append_character)
  end

  private

  def replace_stdio(stdin, stdout)
    orig_stdin = STDIN.dup
    orig_stdout = STDOUT.dup
    STDIN.reopen(stdin)
    STDOUT.reopen(stdout)
    begin
      yield
    ensure
      STDIN.reopen(orig_stdin)
      STDOUT.reopen(orig_stdout)
    end
  end
end

end
