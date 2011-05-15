begin
  require "readline"
=begin
  class << Readline
    [
     "line_buffer",
     "point",
     "set_screen_size",
     "get_screen_size",
     "vi_editing_mode",
     "emacs_editing_mode",
     "completion_append_character=",
     "completion_append_character",
     "basic_word_break_characters=",
     "basic_word_break_characters",
     "completer_word_break_characters=",
     "completer_word_break_characters",
     "basic_quote_characters=",
     "basic_quote_characters",
     "completer_quote_characters=",
     "completer_quote_characters",
     "filename_quote_characters=",
     "filename_quote_characters",
     "refresh_line",
    ].each do |method_name|
      define_method(method_name.to_sym) do |*args|
        raise NotImplementedError
      end
    end
  end
=end
rescue LoadError
else
  require "test/unit"
  require "tempfile"
end

class TestReadline < Test::Unit::TestCase
  def teardown
    Readline.instance_variable_set("@completion_proc", nil)
  end

  def test_safe_level_4
    method_args =
      [
       ["readline"],
       ["input=", $stdin],
       ["output=", $stdout],
       ["completion_proc=", proc {}],
       ["completion_proc"],
       ["completion_case_fold=", true],
       ["completion_case_fold"],
       ["vi_editing_mode"],
       ["vi_editing_mode?"],
       ["emacs_editing_mode"],
       ["emacs_editing_mode?"],
       ["completion_append_character=", "s"],
       ["completion_append_character"],
       ["basic_word_break_characters=", "s"],
       ["basic_word_break_characters"],
       ["completer_word_break_characters=", "s"],
       ["completer_word_break_characters"],
       ["basic_quote_characters=", "\\"],
       ["basic_quote_characters"],
       ["completer_quote_characters=", "\\"],
       ["completer_quote_characters"],
       ["filename_quote_characters=", "\\"],
       ["filename_quote_characters"],
       ["line_buffer"],
       ["point"],
       ["set_screen_size", 1, 1],
       ["get_screen_size"],
      ]
    method_args.each do |method_name, *args|
      assert_raise(SecurityError, NotImplementedError,
                    "method=<#{method_name}>") do
        Thread.start {
          $SAFE = 4
          Readline.send(method_name.to_sym, *args)
          assert(true)
        }.join
      end
    end
  end

  if !/EditLine/n.match(Readline::VERSION)
    def test_readline
      stdin = Tempfile.new("test_readline_stdin")
      stdout = Tempfile.new("test_readline_stdout")
      begin
        stdin.write("hello\n")
        stdin.close
        stdout.close
        line = replace_stdio(stdin.path, stdout.path) {
          Readline.readline("> ", true)
        }
        assert_equal("hello", line)
        assert_equal(true, line.tainted?)
        stdout.open
        assert_equal("> ", stdout.read(2))
        assert_equal(1, Readline::HISTORY.length)
        assert_equal("hello", Readline::HISTORY[0])
        assert_raise(SecurityError) do
          Thread.start {
            $SAFE = 1
            replace_stdio(stdin.path, stdout.path) do
              Readline.readline("> ".taint)
            end
          }.join
        end
        assert_raise(SecurityError) do
          Thread.start {
            $SAFE = 4
            replace_stdio(stdin.path, stdout.path) { Readline.readline("> ") }
          }.join
        end
      ensure
        stdin.close(true)
        stdout.close(true)
      end
    end

    # line_buffer
    # point
    def test_line_buffer__point
      begin
        Readline.line_buffer
        Readline.point
      rescue NotImplementedError
        return
      end

      stdin = Tempfile.new("test_readline_stdin")
      stdout = Tempfile.new("test_readline_stdout")
      begin
        actual_text = nil
        actual_line_buffer = nil
        actual_point = nil
        Readline.completion_proc = proc { |text|
          actual_text = text
          actual_point = Readline.point
          actual_buffer_line = Readline.line_buffer
          stdin.write(" finish\n")
          stdin.close
          stdout.close
          return ["complete"]
        }
        stdin.write("first second\t")
        stdin.flush
        line = replace_stdio(stdin.path, stdout.path) {
          Readline.readline("> ", false)
        }
        assert_equal("first second", actual_line_buffer)
        assert_equal(12, actual_point)
        assert_equal("first complete finish", Readline.line_buffer)
        assert_equal(Encoding.find("locale"), Readline.line_buffer.encoding)
        assert_equal(true, Readline.line_buffer.tainted?)
        assert_equal(21, Readline.point)
      ensure
        stdin.close(true)
        stdout.close(true)
      end
    end
  end

  def test_input=
    assert_raise(TypeError) do
      Readline.input = "This is not a file."
    end
  end

  def test_output=
    assert_raise(TypeError) do
      Readline.output = "This is not a file."
    end
  end

  def test_completion_proc
    expected = proc { |input| input }
    Readline.completion_proc = expected
    assert_equal(expected, Readline.completion_proc)

    assert_raise(ArgumentError) do
      Readline.completion_proc = "This does not have call method."
    end
  end

  def test_completion_case_fold
    expected = [true, false, "string", {"a" => "b"}]
    expected.each do |e|
      Readline.completion_case_fold = e
      assert_equal(e, Readline.completion_case_fold)
    end
  end

  def test_get_screen_size
    begin
      res = Readline.get_screen_size
      assert(res.is_a?(Array))
      rows, columns = *res
      assert(rows.is_a?(Integer))
      assert(rows >= 0)
      assert(columns.is_a?(Integer))
      assert(columns >= 0)
    rescue NotImplementedError
    end
  end

  # vi_editing_mode
  # emacs_editing_mode
  def test_editing_mode
    begin
      assert_equal(false, Readline.vi_editing_mode?)
      assert_equal(true, Readline.emacs_editing_mode?)

      assert_equal(nil, Readline.vi_editing_mode)
      assert_equal(true, Readline.vi_editing_mode?)
      assert_equal(false, Readline.emacs_editing_mode?)
      assert_equal(nil, Readline.vi_editing_mode)
      assert_equal(true, Readline.vi_editing_mode?)
      assert_equal(false, Readline.emacs_editing_mode?)

      assert_equal(nil, Readline.emacs_editing_mode)
      assert_equal(false, Readline.vi_editing_mode?)
      assert_equal(true, Readline.emacs_editing_mode?)
      assert_equal(nil, Readline.emacs_editing_mode)
      assert_equal(false, Readline.vi_editing_mode?)
      assert_equal(true, Readline.emacs_editing_mode?)
    rescue NotImplementedError
    end
  end

  def test_completion_append_character
    begin
      enc = get_default_internal_encoding
      data_expected = [
                       ["x", "x"],
                       ["xyx", "x"],
                       [" ", " "],
                       ["\t", "\t"],
                      ]
      data_expected.each do |(data, expected)|
        Readline.completion_append_character = data
        assert_equal(expected, Readline.completion_append_character)
        assert_equal(enc, Readline.completion_append_character.encoding)
      end
      Readline.completion_append_character = ""
      assert_equal(nil, Readline.completion_append_character)
    rescue NotImplementedError
    end
  end

  # basic_word_break_characters
  # completer_word_break_characters
  # basic_quote_characters
  # completer_quote_characters
  # filename_quote_characters
  def test_some_characters_methods
    method_names = [
                    "basic_word_break_characters",
                    "completer_word_break_characters",
                    "basic_quote_characters",
                    "completer_quote_characters",
                    "filename_quote_characters",
                   ]
    method_names.each do |method_name|
      begin
        begin
          enc = get_default_internal_encoding
          saved = Readline.send(method_name.to_sym)
          expecteds = [" ", " .,|\t", ""]
          expecteds.each do |e|
            Readline.send((method_name + "=").to_sym, e)
            res = Readline.send(method_name.to_sym)
            assert_equal(e, res)
            assert_equal(enc, res.encoding)
          end
        ensure
          Readline.send((method_name + "=").to_sym, saved) if saved
        end
      rescue NotImplementedError
      end
    end
  end

  private

  def replace_stdio(stdin_path, stdout_path)
    open(stdin_path, "r"){|stdin|
      open(stdout_path, "w"){|stdout|
        orig_stdin = STDIN.dup
        orig_stdout = STDOUT.dup
        STDIN.reopen(stdin)
        STDOUT.reopen(stdout)
        begin
          Readline.input = STDIN
          Readline.output = STDOUT
          yield
        ensure
          STDIN.reopen(orig_stdin)
          STDOUT.reopen(orig_stdout)
          orig_stdin.close
          orig_stdout.close
        end
      }
    }
  end

  def get_default_internal_encoding
    return Encoding.default_internal || Encoding.find("locale")
  end
end if defined?(::Readline)
