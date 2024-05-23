# frozen_string_literal: false
require_relative "helper"
require "test/unit"
require "tempfile"
require "timeout"
require "open3"

module BasetestReadline
  RUBY = EnvUtil.rubybin

  INPUTRC = "INPUTRC"
  TERM = "TERM"
  SAVED_ENV = %w[COLUMNS LINES]

  TIMEOUT = 8

  def setup
    @saved_env = ENV.values_at(*SAVED_ENV)
    @inputrc, ENV[INPUTRC] = ENV[INPUTRC], IO::NULL
    @term, ENV[TERM] = ENV[TERM], "vt100"
  end

  def teardown
    ENV[INPUTRC] = @inputrc
    ENV[TERM] = @term
    Readline.instance_variable_set("@completion_proc", nil)
    begin
      Readline.delete_text
      Readline.point = 0
    rescue NotImplementedError
    end
    Readline.special_prefixes = ""
    Readline.completion_append_character = nil
    Readline.input = nil
    Readline.output = nil
    SAVED_ENV.each_with_index {|k, i| ENV[k] = @saved_env[i] }
  end

  def test_readline
    Readline::HISTORY.clear
    omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
    with_temp_stdio do |stdin, stdout|
      stdin.write("hello\n")
      stdin.close
      stdout.flush
      line = replace_stdio(stdin.path, stdout.path) {
        Readline.readline("> ", true)
      }
      assert_equal("hello", line)
      assert_equal(true, line.tainted?) if RUBY_VERSION < '2.7'
      stdout.rewind
      assert_equal("> ", stdout.read(2))
      assert_equal(1, Readline::HISTORY.length)
      assert_equal("hello", Readline::HISTORY[0])

      # Work around lack of SecurityError in Reline
      # test mode with tainted prompt.
      # Also skip test on Ruby 2.7+, where $SAFE/taint is deprecated.
      if RUBY_VERSION < '2.7' && defined?(TestRelineAsReadline) && !kind_of?(TestRelineAsReadline)
        begin
          Thread.start {
            $SAFE = 1
            assert_raise(SecurityError) do
              replace_stdio(stdin.path, stdout.path) do
                Readline.readline("> ".taint)
              end
            end
          }.join
        ensure
          $SAFE = 0
        end
      end
    end
  end

  # line_buffer
  # point
  def test_line_buffer__point
    omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
    omit "GNU Readline has special behaviors" if defined?(Reline) and Readline == Reline
    begin
      Readline.line_buffer
      Readline.point
    rescue NotImplementedError
      return
    end

    with_temp_stdio do |stdin, stdout|
      actual_text = nil
      actual_line_buffer = nil
      actual_point = nil
      Readline.completion_proc = ->(text) {
        actual_text = text
        actual_point = Readline.point
        actual_line_buffer = Readline.line_buffer
        stdin.write(" finish\n")
        stdin.flush
        stdout.flush
        return ["complete"]
      }

      stdin.write("first second\t")
      stdin.flush
      Readline.completion_append_character = " "
      replace_stdio(stdin.path, stdout.path) {
        Readline.readline("> ", false)
      }
      assert_equal("second", actual_text)
      assert_equal("first second", actual_line_buffer)
      assert_equal(12, actual_point)
      assert_equal("first complete  finish", Readline.line_buffer)
      assert_equal(Encoding.find("locale"), Readline.line_buffer.encoding)
      assert_equal(true, Readline.line_buffer.tainted?) if RUBY_VERSION < '2.7'

      assert_equal(22, Readline.point)

      stdin.rewind
      stdout.rewind

      stdin.write("first second\t")
      stdin.flush
      Readline.completion_append_character = nil
      replace_stdio(stdin.path, stdout.path) {
        Readline.readline("> ", false)
      }
      assert_equal("second", actual_text)
      assert_equal("first second", actual_line_buffer)
      assert_equal(12, actual_point)
      assert_equal("first complete finish", Readline.line_buffer)
      assert_equal(Encoding.find("locale"), Readline.line_buffer.encoding)
      assert_equal(true, Readline.line_buffer.tainted?) if RUBY_VERSION < '2.7'

      assert_equal(21, Readline.point)
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
    completion_case_fold = Readline.completion_case_fold
    expected.each do |e|
      Readline.completion_case_fold = e
      assert_equal(e, Readline.completion_case_fold)
    end
  ensure
    Readline.completion_case_fold = completion_case_fold
  end

  def test_completion_proc_empty_result
    omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
    with_temp_stdio do |stdin, stdout|
      stdin.write("first\t")
      stdin.flush
      Readline.completion_proc = ->(text) {[]}
      line1 = line2 = nil
      replace_stdio(stdin.path, stdout.path) {
        assert_nothing_raised(NoMemoryError) {line1 = Readline.readline("> ")}
        stdin.write("\n")
        stdin.flush
        assert_nothing_raised(NoMemoryError) {line2 = Readline.readline("> ")}
      }
      assert_equal("first", line1)
      assert_equal("", line2)
      begin
        assert_equal("", Readline.line_buffer)
      rescue NotImplementedError
      end
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

  def test_completion_encoding
    omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
    bug5941 = '[Bug #5941]'
    append_character = Readline.completion_append_character
    Readline.completion_append_character = ""
    completion_case_fold = Readline.completion_case_fold
    locale = get_default_internal_encoding
    if locale == Encoding::UTF_8
      enc1 = Encoding::EUC_JP
    else
      enc1 = Encoding::UTF_8
    end
    results = nil
    Readline.completion_proc = ->(text) {results}

    [%W"\u{3042 3042} \u{3042 3044}", %W"\u{fe5b fe5b} \u{fe5b fe5c}"].any? do |w|
      begin
        results = w.map {|s| s.encode(locale)}
      rescue Encoding::UndefinedConversionError
      end
    end or
    begin
      "\xa1\xa2".encode(Encoding::UTF_8, locale)
    rescue
    else
      results = %W"\xa1\xa1 \xa1\xa2".map {|s| s.force_encoding(locale)}
    end or
    begin
      return if assert_under_utf8
      omit("missing test for locale #{locale.name}")
    end
    expected = results[0][0...1]
    Readline.completion_case_fold = false
    assert_equal(expected, with_pipe {|r, w| w << "\t"}, bug5941)
    Readline.completion_case_fold = true
    assert_equal(expected, with_pipe {|r, w| w << "\t"}, bug5941)
    results.map! {|s| s.encode(enc1)}
    assert_raise(Encoding::CompatibilityError, bug5941) do
      with_pipe {|r, w| w << "\t"}
    end
  ensure
    return if /EditLine/n.match(Readline::VERSION)
    Readline.completion_case_fold = completion_case_fold
    Readline.completion_append_character = append_character
  end

  # basic_word_break_characters
  # completer_word_break_characters
  # basic_quote_characters
  # completer_quote_characters
  # filename_quote_characters
  # special_prefixes
  def test_some_characters_methods
  end

  def test_closed_outstream
    bug5803 = '[ruby-dev:45043]'
    IO.pipe do |r, w|
      Readline.input = r
      Readline.output = w
      (w << "##\t").close
      assert_raise(IOError, bug5803) {Readline.readline}
    end
  end

  def test_pre_input_hook
    begin
      pr = proc {}
      Readline.pre_input_hook = pr
      assert_equal(pr, Readline.pre_input_hook)
      Readline.pre_input_hook = nil
      assert_nil(Readline.pre_input_hook)
    rescue NotImplementedError
    end
  end

  def test_point
    omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
    assert_equal(0, Readline.point)
    Readline.insert_text('12345')
    assert_equal(5, Readline.point)

    assert_equal(4, Readline.point=(4))

    Readline.insert_text('abc')
    assert_equal(7, Readline.point)

    assert_equal('1234abc5', Readline.line_buffer)
  rescue NotImplementedError
  end

  def test_insert_text
    omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
    str = "test_insert_text"
    assert_equal(0, Readline.point)
    assert_equal(Readline, Readline.insert_text(str))
    assert_equal(str, Readline.line_buffer)
    assert_equal(16, Readline.point)
    assert_equal(get_default_internal_encoding,
                 Readline.line_buffer.encoding)

    Readline.delete_text(1, 3)
    assert_equal("t_insert_text", Readline.line_buffer)
    Readline.delete_text(11)
    assert_equal("t_insert_te", Readline.line_buffer)
    Readline.delete_text(-3...-1)
    assert_equal("t_inserte", Readline.line_buffer)
    Readline.delete_text(-3..-1)
    assert_equal("t_inse", Readline.line_buffer)
    Readline.delete_text(3..-3)
    assert_equal("t_ise", Readline.line_buffer)
    Readline.delete_text(3, 1)
    assert_equal("t_ie", Readline.line_buffer)
    Readline.delete_text(1..1)
    assert_equal("tie", Readline.line_buffer)
    Readline.delete_text(1...2)
    assert_equal("te", Readline.line_buffer)
    Readline.delete_text
    assert_equal("", Readline.line_buffer)
  rescue NotImplementedError
  end

  def test_delete_text
    omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
    str = "test_insert_text"
    assert_equal(0, Readline.point)
    assert_equal(Readline, Readline.insert_text(str))
    assert_equal(16, Readline.point)
    assert_equal(str, Readline.line_buffer)
    Readline.delete_text

    if !defined?(Reline) or Readline != Reline
      # NOTE: unexpected but GNU Readline's spec
      assert_equal(16, Readline.point)
      assert_equal("", Readline.line_buffer)
      assert_equal(Readline, Readline.insert_text(str))
      assert_equal(32, Readline.point)
      assert_equal("", Readline.line_buffer)
    end
  rescue NotImplementedError
  end

  def test_modify_text_in_pre_input_hook
    omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
    with_temp_stdio {|stdin, stdout|
      begin
        stdin.write("world\n")
        stdin.close
        Readline.pre_input_hook = proc do
          assert_equal("", Readline.line_buffer)
          Readline.insert_text("hello ")
          Readline.redisplay
        end
        replace_stdio(stdin.path, stdout.path) do
          line = Readline.readline("> ")
          assert_equal("hello world", line)
        end
        # Readline 4.3 doesn't include inserted text or input
        # Reline's rendering logic is tricky
        if Readline::VERSION != '4.3' and (!defined?(Reline) or Readline != Reline)
          assert_equal("> hello world\n", stdout.read)
        end
        stdout.close
      rescue NotImplementedError
      ensure
        begin
          Readline.pre_input_hook = nil
        rescue NotImplementedError
        end
      end
    }
  end

  def test_input_metachar
    omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
    # test will pass on Windows reline, but not readline
    omit "Won't pass on mingw readline.so using 8.0.001" if /mingw/ =~ RUBY_PLATFORM and defined?(TestReadline) and kind_of?(TestReadline)
    omit 'Needs GNU Readline 6 or later' if /mswin|mingw/ =~ RUBY_PLATFORM and defined?(TestReadline) and kind_of?(TestReadline) and Readline::VERSION < '6.0'
    bug6601 = '[ruby-core:45682]'
    Readline::HISTORY << "hello"
    wo = nil
    line = with_pipe do |r, w|
      wo = w.dup
      wo.write("\C-re\ef\n")
    end
    assert_equal("hello", line, bug6601)
  ensure
    wo&.close
    return if /EditLine/n.match(Readline::VERSION)
    Readline.delete_text
    Readline::HISTORY.clear
  end

  def test_input_metachar_multibyte
    omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
    unless Encoding.find("locale") == Encoding::UTF_8
      return if assert_under_utf8
      omit 'this test needs UTF-8 locale'
    end
    bug6602 = '[ruby-core:45683]'
    Readline::HISTORY << "\u3042\u3093"
    Readline::HISTORY << "\u3044\u3093"
    Readline::HISTORY << "\u3046\u3093"
    open(IO::NULL, 'w') do |null|
      IO.pipe do |r, w|
        Readline.input = r
        Readline.output = null
        w << "\cr\u3093\n\n"
        w << "\cr\u3042\u3093"
        w.reopen(IO::NULL)
        assert_equal("\u3046\u3093", Readline.readline("", true), bug6602)
        Timeout.timeout(TIMEOUT) do
          assert_equal("\u3042\u3093", Readline.readline("", true), bug6602)
        end
        assert_equal(nil,            Readline.readline("", true), bug6602)
      end
    end
  ensure
    return if /EditLine/n.match(Readline::VERSION)
    Readline.delete_text
    Readline::HISTORY.clear
  end

  def test_refresh_line
    omit "Only when refresh_line exists" unless Readline.respond_to?(:refresh_line)
    omit unless respond_to?(:assert_ruby_status)
    bug6232 = '[ruby-core:43957] [Bug #6232] refresh_line after set_screen_size'
    with_temp_stdio do |stdin, stdout|
      replace_stdio(stdin.path, stdout.path) do
        assert_ruby_status(%w[-rreadline -], <<-'end;', bug6232)
          Readline.set_screen_size(40, 80)
          Readline.refresh_line
        end;
      end
    end
  end

  # TODO Green CI for arm32-linux (Travis CI), and Readline 7.0.
  def test_interrupt_in_other_thread
    # Editline and Readline 7.0 can't treat I/O that is not tty.
    omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
    omit "Skip Readline 7.0" if Readline::VERSION == "7.0"
    omit unless respond_to?(:assert_ruby_status)
    omit if /mswin|mingw/ =~ RUBY_PLATFORM

    # On 32-bit machine, readline library (or libtinfo) seems to cause SEGV internally even with Readline 8.0
    # GDB Backtrace: https://gist.github.com/mame/d12b9de3bbc3f16d440c1927398d176a
    # Maybe the same issue: https://github.com/facebookresearch/nle/issues/120
    omit if /i[3-6]86-linux/ =~ RUBY_PLATFORM

    # Skip arm32-linux (Travis CI).  See aefc988 in main ruby repo.
    omit "Skip arm32-linux" if /armv[0-9+][a-z]-linux/ =~ RUBY_PLATFORM

    if defined?(TestReadline) && self.class == TestReadline
      use = "use_ext_readline"
    elsif defined?(TestRelineAsReadline) && self.class == TestRelineAsReadline
      use = "use_lib_reline"
    end
    code = <<-"end;"
      $stdout.sync = true
      require 'readline'
      require 'helper'
      #{use}
      puts "Readline::VERSION is \#{Readline::VERSION}."
      Readline.input = STDIN
      # 0. Send SIGINT to this script.
      begin
        Thread.new{
          trap(:INT) {
            puts 'TRAP' # 2. Show 'TRAP' message.
          }
          Readline.readline('input> ') # 1. Should keep working and call old trap.
                                       # 4. Receive "\\n" and return because still working.
        }.value
      rescue Interrupt
        puts 'FAILED' # 3. "Interrupt" shouldn't be raised because trapped.
        raise
      end
      puts 'SUCCEEDED' # 5. Finish correctly.
    end;

    script = Tempfile.new("interrupt_in_other_thread")
    script.write code
    script.close

    log = String.new

    EnvUtil.invoke_ruby(["-I#{__dir__}", script.path], "", true, :merge_to_stdout) do |_in, _out, _, pid|
      Timeout.timeout(TIMEOUT) do
        log << "** START **"
        loop do
          c = _out.read(1)
          log << c if c
          break if log.include?('input> ')
        end
        log << "** SIGINT **"
        sleep 0.5
        Process.kill(:INT, pid)
        sleep 0.5
        loop do
          c = _out.read(1)
          log << c if c
          break if log.include?('TRAP')
        end
        begin
          log << "** NEWLINE **"
          _in.write "\n"
        rescue Errno::EPIPE
          log << "** Errno::EPIPE **"
          # The "write" will fail if Reline crashed by SIGINT.
        end
        interrupt_suppressed = nil
        loop do
          c = _out.read(1)
          log << c if c
          if log.include?('FAILED')
            interrupt_suppressed = false
            break
          end
          if log.include?('SUCCEEDED')
            interrupt_suppressed = true
            break
          end
        end
        assert interrupt_suppressed, "Should handle SIGINT correctly but raised interrupt.\nLog: #{log}\n----"
      end
    rescue Timeout::Error => e
      Process.kill(:KILL, pid)
      log << "\nKilled by timeout"
      assert false, "Timed out to handle SIGINT!\nLog: #{log}\nBacktrace:\n#{e.full_message(highlight: false)}\n----"
    ensure
      status = nil
      begin
        Timeout.timeout(TIMEOUT) do
          status = Process.wait2(pid).last
        end
      rescue Timeout::Error => e
        log << "\nKilled by timeout to wait2"
        Process.kill(:KILL, pid)
        assert false, "Timed out to wait for terminating a process in a test of SIGINT!\nLog: #{log}\nBacktrace:\n#{e.full_message(highlight: false)}\n----"
      end
      assert status&.success?, "Unknown failure with exit status #{status.inspect}\nLog: #{log}\n----"
    end

    assert log.include?('INT'), "Interrupt was handled correctly."
  ensure
    script&.close!
  end

  def test_setting_quoting_detection_proc
    return unless Readline.respond_to?(:quoting_detection_proc=)

    expected = proc { |text, index| false }
    Readline.quoting_detection_proc = expected
    assert_equal(expected, Readline.quoting_detection_proc)

    assert_raise(ArgumentError) do
      Readline.quoting_detection_proc = "This does not have call method."
    end
  end

  def test_using_quoting_detection_proc
    saved_completer_quote_characters = Readline.completer_quote_characters
    saved_completer_word_break_characters = Readline.completer_word_break_characters

    # skip if previous value is nil because Readline... = nil is not allowed.
    omit "No completer_quote_characters" unless saved_completer_quote_characters
    omit "No completer_word_break_characters" unless saved_completer_word_break_characters

    return unless Readline.respond_to?(:quoting_detection_proc=)

    begin
      passed_text = nil
      line = nil

      with_temp_stdio do |stdin, stdout|
        replace_stdio(stdin.path, stdout.path) do
          Readline.completion_proc = ->(text) do
            passed_text = text
            ['completion'].map { |i|
              i.encode(Encoding.default_external)
            }
          end
          Readline.completer_quote_characters = '\'"'
          Readline.completer_word_break_characters = ' '
          Readline.quoting_detection_proc = ->(text, index) do
            index > 0 && text[index-1] == '\\'
          end

          stdin.write("first second\\ third\t")
          stdin.flush
          line = Readline.readline('> ', false)
        end
      end

      assert_equal('second\\ third', passed_text)
      assert_equal('first completion', line.chomp(' '))
    ensure
      Readline.completer_quote_characters = saved_completer_quote_characters
      Readline.completer_word_break_characters = saved_completer_word_break_characters
    end
  end

  def test_using_quoting_detection_proc_with_multibyte_input
    Readline.completion_append_character = nil
    saved_completer_quote_characters = Readline.completer_quote_characters
    saved_completer_word_break_characters = Readline.completer_word_break_characters

    # skip if previous value is nil because Readline... = nil is not allowed.
    omit "No completer_quote_characters" unless saved_completer_quote_characters
    omit "No completer_word_break_characters" unless saved_completer_word_break_characters

    return unless Readline.respond_to?(:quoting_detection_proc=)
    unless get_default_internal_encoding == Encoding::UTF_8
      return if assert_under_utf8
      omit 'this test needs UTF-8 locale'
    end

    begin
      passed_text = nil
      escaped_char_indexes = []
      line = nil

      with_temp_stdio do |stdin, stdout|
        replace_stdio(stdin.path, stdout.path) do
          Readline.completion_proc = ->(text) do
            passed_text = text
            ['completion'].map { |i|
              i.encode(Encoding.default_external)
            }
          end
          Readline.completer_quote_characters = '\'"'
          Readline.completer_word_break_characters = ' '
          Readline.quoting_detection_proc = ->(text, index) do
            escaped = index > 0 && text[index-1] == '\\'
            escaped_char_indexes << index if escaped
            escaped
          end

          stdin.write("\u3042\u3093 second\\ third\t")
          stdin.flush
          line = Readline.readline('> ', false)
        end
      end

      assert_equal([10], escaped_char_indexes)
      assert_equal('second\\ third', passed_text)
      assert_equal("\u3042\u3093 completion#{Readline.completion_append_character}", line)
    ensure
      Readline.completer_quote_characters = saved_completer_quote_characters
      Readline.completer_word_break_characters = saved_completer_word_break_characters
    end
  end

  def test_simple_completion
    omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)

    line = nil

    open(IO::NULL, 'w') do |null|
      IO.pipe do |r, w|
        Readline.input = r
        Readline.output = null
        Readline.completion_proc = ->(text) do
          ['abcde', 'abc12'].map { |i|
            i.encode(get_default_internal_encoding)
          }
        end
        w.write("a\t\n")
        w.flush
        begin
          stderr = $stderr.dup
          $stderr.reopen(null)
          line = Readline.readline('> ', false)
        ensure
          $stderr.reopen(stderr)
          stderr.close
        end
      end
    end

    assert_equal('abc', line)
  end

  def test_completion_with_completion_append_character
    omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
    omit "Readline.completion_append_character is not implemented" unless Readline.respond_to?(:completion_append_character=)
    line = nil

    append_character = Readline.completion_append_character
    open(IO::NULL, 'w') do |null|
      IO.pipe do |r, w|
        Readline.input = r
        Readline.output = null
        Readline.completion_append_character = '!'
        Readline.completion_proc = ->(text) do
          ['abcde'].map { |i|
            i.encode(get_default_internal_encoding)
          }
        end
        w.write("a\t\n")
        w.flush
        line = Readline.readline('> ', false)
      end
    end

    assert_equal('abcde!', line)
  ensure
    return if /EditLine/n.match(Readline::VERSION)
    return unless Readline.respond_to?(:completion_append_character=)
    Readline.completion_append_character = append_character
  end

  def test_completion_quote_character_completing_unquoted_argument
    return unless Readline.respond_to?(:completion_quote_character)

    saved_completer_quote_characters = Readline.completer_quote_characters

    quote_character = "original value"
    Readline.completion_proc = -> (_) do
      quote_character = Readline.completion_quote_character
      []
    end
    Readline.completer_quote_characters = "'\""

    with_temp_stdio do |stdin, stdout|
      replace_stdio(stdin.path, stdout.path) do
        stdin.write("input\t")
        stdin.flush
        Readline.readline("> ", false)
      end
    end

    assert_nil(quote_character)
  ensure
    Readline.completer_quote_characters = saved_completer_quote_characters if saved_completer_quote_characters
  end

  def test_completion_quote_character_completing_quoted_argument
    return unless Readline.respond_to?(:completion_quote_character)

    saved_completer_quote_characters = Readline.completer_quote_characters

    quote_character = "original value"
    Readline.completion_proc = -> (_) do
      quote_character = Readline.completion_quote_character
      []
    end
    Readline.completer_quote_characters = "'\""

    with_temp_stdio do |stdin, stdout|
      replace_stdio(stdin.path, stdout.path) do
        stdin.write("'input\t")
        stdin.flush
        Readline.readline("> ", false)
      end
    end

    assert_equal("'", quote_character)
  ensure
    Readline.completer_quote_characters = saved_completer_quote_characters if saved_completer_quote_characters
  end

  def test_completion_quote_character_after_completion
    return unless Readline.respond_to?(:completion_quote_character)
    if /solaris/i =~ RUBY_PLATFORM
      # http://rubyci.s3.amazonaws.com/solaris11s-sunc/ruby-trunk/log/20181228T102505Z.fail.html.gz
      omit 'This test does not succeed on Oracle Developer Studio for now'
    end
    omit 'Needs GNU Readline 6 or later' if /mswin|mingw/ =~ RUBY_PLATFORM and defined?(TestReadline) and kind_of?(TestReadline) and Readline::VERSION < '6.0'

    saved_completer_quote_characters = Readline.completer_quote_characters

    Readline.completion_proc = -> (_) { [] }
    Readline.completer_quote_characters = "'\""

    with_temp_stdio do |stdin, stdout|
      replace_stdio(stdin.path, stdout.path) do
        stdin.write("'input\t")
        stdin.flush
        Readline.readline("> ", false)
      end
    end

    assert_nil(Readline.completion_quote_character)
  ensure
    Readline.completer_quote_characters = saved_completer_quote_characters if saved_completer_quote_characters
  end

  def test_without_tty
    omit "Skip Editline" if /EditLine/n.match(Readline::VERSION)
    loader = nil
    if defined?(TestReadline) && self.class == TestReadline
      loader = "use_ext_readline"
    elsif defined?(TestRelineAsReadline) && self.class == TestRelineAsReadline
      loader = "use_lib_reline"
    end
    if loader
      res, exit_status = Open3.capture2e("#{RUBY} -I#{__dir__} -Ilib -rhelper -e '#{loader}; Readline.readline(%{y or n?})'", stdin_data: "y\n")
      assert exit_status.success?, "It should work fine without tty, but it failed.\nError output:\n#{res}"
    end
  end

  private

  def replace_stdio(stdin_path, stdout_path)
    open(stdin_path, "r"){|stdin|
      open(stdout_path, "w"){|stdout|
        orig_stdin = STDIN.dup
        orig_stdout = STDOUT.dup
        orig_stderr = STDERR.dup
        STDIN.reopen(stdin)
        STDOUT.reopen(stdout)
        STDERR.reopen(stdout)
        begin
          Readline.input = STDIN
          Readline.output = STDOUT
          yield
        ensure
          STDERR.reopen(orig_stderr)
          STDIN.reopen(orig_stdin)
          STDOUT.reopen(orig_stdout)
          orig_stdin.close
          orig_stdout.close
          orig_stderr.close
        end
      }
    }
  end

  def with_temp_stdio
    Tempfile.create("test_readline_stdin") {|stdin|
      Tempfile.create("test_readline_stdout") {|stdout|
        yield stdin, stdout
        if /mswin|mingw/ =~ RUBY_PLATFORM
          # needed since readline holds refs to tempfiles, can't delete on Windows
          Readline.input = STDIN
          Readline.output = STDOUT
        end
      }
    }
  end

  def with_pipe
    stderr = nil
    IO.pipe do |r, w|
      yield(r, w)
      Readline.input = r
      Readline.output = w.reopen(IO::NULL)
      stderr = STDERR.dup
      STDERR.reopen(w)
      Readline.readline
    end
  ensure
    if stderr
      STDERR.reopen(stderr)
      stderr.close
    end
    Readline.input = STDIN
    Readline.output = STDOUT
  end

  def get_default_internal_encoding
    return Encoding.default_internal || Encoding.find("locale")
  end

  def assert_under_utf8
    return false if ENV['LC_ALL'] == 'UTF-8'
    loc = caller_locations(1, 1)[0].base_label.to_s
    assert_separately([{"LC_ALL"=>"UTF-8"}, "-r", __FILE__], <<SRC)
#omit "test \#{ENV['LC_ALL']}"
#{self.class.name}.new(#{loc.dump}).run(Test::Unit::Runner.new)
SRC
    return true
  end
end

class TestReadline < Test::Unit::TestCase
  include BasetestReadline

  def setup
    use_ext_readline
    super
  end
end if defined?(ReadlineSo) && ENV["TEST_READLINE_OR_RELINE"] != "Reline"

class TestRelineAsReadline < Test::Unit::TestCase
  include BasetestReadline

  def setup
    use_lib_reline
    super
  end

  def teardown
    finish_using_lib_reline
    super
  end

  def get_default_internal_encoding
    if RUBY_PLATFORM =~ /mswin|mingw/
      Encoding.default_internal || Encoding::UTF_8
    else
      Reline::IOGate.encoding
    end
  end
end if defined?(Reline) && ENV["TEST_READLINE_OR_RELINE"] != "Readline"
