# frozen_string_literal: false
begin
  require 'io/console'
  require 'test/unit'
  require 'pty'
rescue LoadError
end

class TestIO_Console < Test::Unit::TestCase
  def test_console_namespace
    assert_kind_of(Module, IO::Console)
  end unless RUBY_ENGINE == "jruby" && RbConfig::CONFIG["host_os"] !~ /mswin|mingw/

  HOST_OS = RbConfig::CONFIG['host_os']

  def test_version
    assert_kind_of(String, IO::Console::VERSION)
    EnvUtil.suppress_warning do
      assert_same(IO::Console::VERSION, IO::Console::Mode::VERSION)
    end
  end

  private def host_os?(os)
    HOST_OS =~ os
  end

  begin
    PATHS = $LOADED_FEATURES.grep(%r"/io/console(?:\.#{RbConfig::CONFIG['DLEXT']}|\.rb|/\w+\.rb)\z") {$`}
  rescue Encoding::CompatibilityError
    $stderr.puts "test_io_console.rb debug"
    $LOADED_FEATURES.each{|path| $stderr.puts [path, path.encoding].inspect}
    raise
  end
  PATHS.uniq!
  INCLUDE_OPTS = "-I#{PATHS.join(File::PATH_SEPARATOR)}"

  # FreeBSD seems to hang on TTOU when running parallel tests
  # tested on FreeBSD 11.x.
  #
  # I suspect that it occurs only when having no TTY.
  # (Parallel mode runs tests in child processes, so I guess
  # they has no TTY.)
  # But it does not occur in `make test-all > /dev/null`, so
  # there should be an additional factor, I guess.
  def set_winsize_setup
    @old_ttou = trap(:TTOU, 'IGNORE') if host_os?(/freebsd/)
  end

  def set_winsize_teardown
    trap(:TTOU, @old_ttou) if defined?(@old_ttou) and @old_ttou
  end

  exceptions = %w[ENODEV ENOTTY EBADF ENXIO].map {|e|
    Errno.const_get(e) if Errno.const_defined?(e)
  }
  exceptions.compact!
  FailedPathExceptions = (exceptions unless exceptions.empty?)

  def test_failed_path
    File.open(IO::NULL) do |f|
      e = assert_raise(*FailedPathExceptions) do
        f.echo?
      end
      assert_include(e.message, IO::NULL)
    end
  end if FailedPathExceptions

  def test_bad_keyword
    assert_raise_with_message(ArgumentError, /unknown keyword:.*bad/) do
      File.open(IO::NULL) do |f|
        f.raw(bad: 0)
      end
    end
  end

  TTY_ENHANCED = IO.instance_method(:tty?).arity != 0

  def test_tty?
    pend "not supported" unless TTY_ENHANCED

    tty = STDIN.tty?(:any)
    assert_include([true, false], tty)
    assert_equal(tty, STDIN.tty?(:any, :any))
    assert_equal(tty, STDIN.tty?(nil, :any))
    assert_equal(STDIN.tty?, STDIN.tty?(nil))
  end

  def test_tty_non_tty
    pend "not supported" unless TTY_ENHANCED

    File.open(IO::NULL) do |f|
      assert_not_predicate(f, :tty?)
      assert_not_operator(f, :tty?, :any)
      assert_not_operator(f, :tty?, nil)
      assert_not_send([f, :tty?, :any, :any])
      assert_not_send([f, :tty?, nil, :any])

      assert_raise(TypeError) {f.tty?("any")}
      assert_raise(ArgumentError) {f.tty?(:unknown)}
    end
  end
end

defined?(PTY) and defined?(IO.console) and \
class TestIO_Console
  Bug6116 = '[ruby-dev:45309]'

  def test_raw
    helper {|m, s|
      s.print "abc\n"
      assert_equal("abc\r\n", m.gets)
      assert_send([s, :echo?])
      s.raw {
        assert_not_send([s, :echo?], Bug6116)
        s.print "def\n"
        assert_equal("def\n", m.gets)
      }
      assert_send([s, :echo?])
      s.print "ghi\n"
      assert_equal("ghi\r\n", m.gets)
    }
  end

  def test_raw_minchar
    q = Thread::Queue.new
    helper {|m, s|
      len = 0
      assert_equal([nil, 0], [s.getch(min: 0), len])
      main = Thread.current
      go = false
      th = Thread.start {
        q.pop
        sleep 0.01 until main.stop?
        len += 1
        m.print("a")
        m.flush
        sleep 0.01 until go and main.stop?
        len += 10
        m.print("1234567890")
        m.flush
      }
      begin
        sleep 0.1
        q.push(1)
        assert_equal(["a", 1], [s.getch(min: 1), len])
        go = true
        assert_equal(["1", 11], [s.getch, len])
      ensure
        th.join
      end
    }
  end

  def test_raw_timeout
    helper {|m, s|
      len = 0
      assert_equal([nil, 0], [s.getch(min: 0, time: 0.1), len])
      main = Thread.current
      th = Thread.start {
        sleep 0.01 until main.stop?
        len += 2
        m.print("ab")
      }
      begin
        assert_equal(["a", 2], [s.getch(min: 1, time: 1), len])
        assert_equal(["b", 2], [s.getch(time: 1), len])
      ensure
        th.join
      end
    }
  end

  def test_raw!
    helper {|m, s|
      s.raw!
      s.print "foo\n"
      assert_equal("foo\n", m.gets)
    }
  end

  def test_cooked
    helper {|m, s|
      assert_send([s, :echo?])
      s.raw {
        s.print "abc\n"
        assert_equal("abc\n", m.gets)
        assert_not_send([s, :echo?], Bug6116)
        s.cooked {
          assert_send([s, :echo?])
          s.print "def\n"
          assert_equal("def\r\n", m.gets)
        }
        assert_not_send([s, :echo?], Bug6116)
      }
      assert_send([s, :echo?])
      s.print "ghi\n"
      assert_equal("ghi\r\n", m.gets)
    }
  end

  def test_echo
    helper {|m, s|
      assert_send([s, :echo?])
      m.print "a"
      assert_equal("a", m.readpartial(10))
    }
  end

  def test_noecho
    helper {|m, s|
      s.noecho {
	assert_not_send([s, :echo?])
	m.print "a"
	m.flush
	assert_equal("a", s.getch)
      }
      m.print "b"
      assert_equal("b", m.readpartial(10))
    }
  end

  def test_noecho2
    helper {|m, s|
      assert_send([s, :echo?])
      m.print "a\n"
      sleep 0.1
      s.print "b\n"
      sleep 0.1
      assert_equal("a\r\nb\r\n", m.gets + m.gets)
      assert_equal("a\n", s.gets)
      s.noecho {
        assert_not_send([s, :echo?])
        m.print "a\n"
        s.print "b\n"
        assert_equal("b\r\n", m.gets)
        assert_equal("a\n", s.gets)
      }
      assert_send([s, :echo?])
      m.print "a\n"
      sleep 0.1
      s.print "b\n"
      sleep 0.1
      assert_equal("a\r\nb\r\n", m.gets + m.gets)
      assert_equal("a\n", s.gets)
    }
  end

  def test_setecho
    helper {|m, s|
      assert_send([s, :echo?])
      s.echo = false
      m.print "a"
      sleep 0.1
      s.echo = true
      m.print "b"
      assert_equal("b", m.readpartial(10))
    }
  end

  def test_setecho2
    helper {|m, s|
      assert_send([s, :echo?])
      m.print "a\n"
      sleep 0.1
      s.print "b\n"
      sleep 0.1
      assert_equal("a\r\nb\r\n", m.gets + m.gets)
      assert_equal("a\n", s.gets)
      s.echo = false
      assert_not_send([s, :echo?])
      m.print "a\n"
      s.print "b\n"
      assert_equal("b\r\n", m.gets)
      assert_equal("a\n", s.gets)
      s.echo = true
      assert_send([s, :echo?])
      m.print "a\n"
      sleep 0.1
      s.print "b\n"
      sleep 0.1
      assert_equal("a\r\nb\r\n", m.gets + m.gets)
      assert_equal("a\n", s.gets)
    }
  end

  def test_console_mode
    helper {|m, s|
      begin
        original = s.console_mode
        assert_kind_of(IO::Console::Mode, original)
        EnvUtil.suppress_warning do
          assert_same(IO::Console::Mode, IO.const_get(:ConsoleMode))
        end

        noecho = original.dup
        noecho.echo = false
        assert_same(noecho, s.send(:console_mode=, noecho))
        assert_not_predicate(s, :echo?)

        raw = original.raw
        assert_not_same(original, raw)
        assert_same(raw, raw.raw!)
        assert_same(raw, s.send(:console_mode=, raw))
        s.print "raw\n"
        assert_equal("raw\n", m.gets)
      ensure
        s.console_mode = original if original
      end
    }
  end

  def test_stty_redirect_stdout
    helper do |_, s|
      stdout = STDOUT.dup
      begin
        STDOUT.reopen(s)
        mode = STDOUT.__send__(:_io_console_stty, "-g")
      ensure
        STDOUT.reopen(stdout)
        stdout.close
      end
      assert_not_empty(mode)
    end
  end if IO.private_method_defined?(:_io_console_stty)

  def test_tty_on_pty
    pend "not supported" unless TTY_ENHANCED

    helper {|_, s|
      assert_predicate(s, :tty?)
      assert_operator(s, :tty?, :any)
      assert_operator(s, :tty?, nil)
      assert_send([s, :tty?, :any, :any])
      assert_send([s, :tty?, nil, :any])

      assert_raise(TypeError) {s.tty?("any")}
      assert_raise(ArgumentError) {s.tty?(:unknown)}
    }
  end

  def test_getpass
    run_pty("p IO.console.getpass('> ')") do |r, w|
      assert_equal("> ", r.readpartial(10))
      sleep 0.1
      w.print "asdf\n"
      sleep 0.1
      assert_equal("\r\n", r.gets)
      assert_equal("\"asdf\"", r.gets.chomp)
    end

    run_pty("p IO.console.getpass('> ')") do |r, w|
      assert_equal("> ", r.readpartial(10))
      sleep 0.1
      w.print "asdf\C-D\C-D"
      sleep 0.1
      assert_equal("\r\n", r.gets)
      assert_equal("\"asdf\"", r.gets.chomp)
    end

    run_pty("$VERBOSE, $/ = nil, '.'; p IO.console.getpass('> ')") do |r, w|
      assert_equal("> ", r.readpartial(10))
      sleep 0.1
      w.print "asdf\n"
      sleep 0.1
      assert_equal("\r\n", r.gets)
      assert_equal("\"asdf\"", r.gets.chomp)
    end
  end

  def test_getpass_empty
    helper do |m, s|
      result = Thread.new {s.getpass("> ")}
      assert_equal("> ", m.readpartial(10))
      Timeout.timeout(1) {Thread.pass while s.echo?}
      m.write "\C-D"
      assert_nil(result.value)
      assert_equal("\r\n", m.readpartial(10))
    end
  end

  def test_iflush
    pend "stty cannot flush terminal queues" if IO.private_method_defined?(:_io_console_stty)

    helper {|m, s|
      m.print "a"
      s.iflush
      m.print "b\n"
      m.flush
      assert_equal("b\n", s.gets)
    }
  end

  def test_oflush
    helper {|m, s|
      s.print "a"
      s.oflush # oflush may be issued after "a" is already sent.
      s.print "b"
      s.flush
      sleep 0.1
      assert_include(["b", "ab"], m.readpartial(10))
    }
  end

  def test_ioflush
    pend "stty cannot flush terminal queues" if IO.private_method_defined?(:_io_console_stty)

    helper {|m, s|
      m.print "a"
      s.ioflush
      m.print "b\n"
      m.flush
      assert_equal("b\n", s.gets)
    }
  end

  def test_ioflush2
    helper {|m, s|
      s.print "a"
      s.ioflush # ioflush may be issued after "a" is already sent.
      s.print "b"
      s.flush
      sleep 0.1
      assert_include(["b", "ab"], m.readpartial(10))
    }
  end

  def test_winsize
    helper {|m, s|
      begin
        assert_equal([0, 0], s.winsize)
      rescue Errno::EINVAL # OpenSolaris 2009.06 TIOCGWINSZ causes Errno::EINVAL before TIOCSWINSZ.
      else
        assert_equal([80, 25], s.winsize = [80, 25])
        assert_equal([80, 25], s.winsize)
        #assert_equal([80, 25], m.winsize)
        assert_equal([100, 40], m.winsize = [100, 40])
        #assert_equal([100, 40], s.winsize)
        assert_equal([100, 40], m.winsize)
      end
    }
  end

  def test_set_winsize_invalid_dev
    set_winsize_setup
    [IO::NULL, __FILE__].each do |path|
      open(path) do |io|
        begin
          s = io.winsize
        rescue SystemCallError => e
          assert_raise(e.class) {io.winsize = [0, 0]}
        else
          assert(false, "winsize on #{path} succeed: #{s.inspect}")
        end
        assert_raise(ArgumentError) {io.winsize = [0, 0, 0]}
      end
    end
  ensure
    set_winsize_teardown
  end

  def test_cursor_position
    run_pty("#{<<~"begin;"}\n#{<<~'end;'}") do |r, w, _|
      begin;
        con = IO.console
        p con.cursor
        con.cursor_down(3); con.puts
        con.cursor_right(4); con.puts
        con.cursor_left(2); con.puts
        con.cursor_up(1); con.puts
        p con.cursor
        p con.cursor
      end;
      assert_equal("\e[6n", r.readpartial(5))
      w.print("\e[12;34R"); w.flush
      assert_equal([11, 33], eval(r.gets))
      assert_equal("\e[3B", r.gets.chomp)
      assert_equal("\e[4C", r.gets.chomp)
      assert_equal("\e[2D", r.gets.chomp)
      assert_equal("\e[1A", r.gets.chomp)

      assert_equal("\e[6n", r.readpartial(5))
      w.print("\e[12R"); w.flush
      assert_equal("nil", r.gets.chomp)

      assert_equal("\e[6n", r.readpartial(5))
      w.print("\e[12;34;56R"); w.flush
      assert_equal("nil", r.gets.chomp)
    end
  end

  def test_cursor_visibility
    run_pty(<<~'RUBY') do |r, _, _|
      con = IO.console
      abort unless con.hide_cursor.equal?(con)
      abort unless con.show_cursor.equal?(con)
    RUBY
      assert_equal("\e[?25l\e[?25h", r.read(12))
    end
  end unless RbConfig::CONFIG["host_os"] =~ /mswin|mingw/

  def test_input_pending
    IO.pipe do |read, write|
      assert_false(read.input_pending?)
      write.write("ab")
      assert_true(read.input_pending?)
      assert_equal("a", read.getc)
      assert_true(read.input_pending?)
      assert_equal("b", read.getc)
      assert_false(read.input_pending?)
    end
  end unless RbConfig::CONFIG["host_os"] =~ /mswin|mingw/ || RUBY_ENGINE == "jruby"

  def assert_ctrl(expect, cc, r, w)
    sleep 0.1
    w.print cc
    w.flush
    result = EnvUtil.timeout(3) {r.gets}
    if result
      case cc.chr
      when "\C-A".."\C-_"
        cc = "^" + (cc.ord | 0x40).chr
      when "\C-?"
        cc = "^?"
      end
      result.sub!(cc, "")
    end
    assert_equal(expect, result.chomp)
  end

  def test_intr
    # This test fails randomly on FreeBSD 13
    # http://rubyci.s3.amazonaws.com/freebsd13/ruby-master/log/20220304T163001Z.fail.html.gz
    #
    #   1) Failure:
    # TestIO_Console#test_intr [/usr/home/chkbuild/chkbuild/tmp/build/20220304T163001Z/ruby/test/io/console/test_io_console.rb:387]:
    # <"25"> expected but was
    # <"-e:12:in `p': \e[1mexecution expired (\e[1;4mTimeout::Error\e[m\e[1m)\e[m">.
    omit if host_os?(/freebsd/)

    run_pty("#{<<~"begin;"}\n#{<<~'end;'}") do |r, w, _|
      begin;
        require 'timeout'
        STDOUT.puts `stty -a`.scan(/\b\w+ *= *\^.;/), ""
        STDOUT.flush
        con = IO.console
        while c = con.getch
          p c.ord
          p con.getch(intr: false).ord
          begin
            p Timeout.timeout(1) {con.getch(intr: true)}.ord
          rescue Timeout::Error, Interrupt => e
            p e
          end
        end
      end;
      ctrl = {}
      r.each do |l|
        break unless /^(\w+) *= *\^(\\?.)/ =~ l
        ctrl[$1] = eval("?\\C-#$2")
      end
      if cc = ctrl["intr"]
        assert_ctrl("#{cc.ord}", cc, r, w)
        assert_ctrl("#{cc.ord}", cc, r, w)
        assert_ctrl("Interrupt", cc, r, w) unless host_os?(/linux/)
      end
      if cc = ctrl["dsusp"]
        assert_ctrl("#{cc.ord}", cc, r, w)
        assert_ctrl("#{cc.ord}", cc, r, w)
        assert_ctrl("#{cc.ord}", cc, r, w)
      end
      if cc = ctrl["lnext"]
        assert_ctrl("#{cc.ord}", cc, r, w)
        assert_ctrl("#{cc.ord}", cc, r, w)
        assert_ctrl("#{cc.ord}", cc, r, w)
      end
      if cc = ctrl["stop"]
        assert_ctrl("#{cc.ord}", cc, r, w)
        assert_ctrl("#{cc.ord}", cc, r, w)
        assert_ctrl("#{cc.ord}", cc, r, w)
      end
    end
  end

  unless IO.console
    def test_close
      assert_equal(["true"], run_pty("IO.console.close; p IO.console.fileno >= 0"))
      assert_equal(["true"], run_pty("IO.console(:close); p IO.console(:tty?)"))
    end

    def test_console_kw
      assert_equal(["File"], run_pty("IO.console.close; p IO.console(:clone, freeze: true).class"))
    end

    def test_sync
      assert_equal(["true"], run_pty("p IO.console.sync"))
    end

    def test_ttyname
      return unless IO.method_defined?(:ttyname)
      # [Bug #20682]
      # `sleep 0.1` is added to stabilize flaky failures on macOS.
      assert_equal(["true"], run_pty("p STDIN.ttyname == STDOUT.ttyname; sleep 0.1"))
    end
  end

  private
  def helper
    m, s = PTY.open
  rescue RuntimeError
    omit $!
  else
    yield m, s
  ensure
    m.close if m
    s.close if s
  end

  def run_pty(src, n = 1)
    pend("PTY.spawn cannot control terminal on JRuby") if RUBY_ENGINE == 'jruby'

    args = [TestIO_Console::INCLUDE_OPTS, "-rio/console", "-e", src]
    args.shift if args.first == "-I" # statically linked
    r, w, pid = PTY.spawn(EnvUtil.rubybin, *args)
  rescue RuntimeError
    omit $!
  else
    if block_given?
      yield r, w, pid
    else
      result = []
      n.times {result << r.gets.chomp}
      result
    end
  ensure
    r.close if r
    w.close if w
    Process.wait(pid) if pid
  end
end

defined?(IO.console) and IO.console and \
class TestIO_Console
  def test_get_winsize_console
    s = IO.console.winsize
    assert_kind_of(Array, s)
    assert_equal(2, s.size)
    assert_kind_of(Integer, s[0])
    assert_kind_of(Integer, s[1])
  end

  def test_set_winsize_console
    set_winsize_setup
    s = IO.console.winsize
    assert_nothing_raised(TypeError) {IO.console.winsize = s}
    bug = '[ruby-core:82741] [Bug #13888]'
    begin
      IO.console.winsize = [s[0], s[1]+1]
      assert_equal([s[0], s[1]+1], IO.console.winsize, bug)
    rescue Errno::EINVAL    # Error if run on an actual console.
    else
      IO.console.winsize = s
      assert_equal(s, IO.console.winsize, bug)
    end
  ensure
    set_winsize_teardown
  end

  def test_close
    IO.console.close
    assert_kind_of(IO, IO.console)
    assert_nothing_raised(IOError) {IO.console.fileno}

    IO.console(:close)
    assert(IO.console(:tty?))
  ensure
    IO.console(:close)
  end

  def test_console_kw
    io = IO.console(:clone, freeze: true)
    io.close
    assert_kind_of(IO, io)
  end

  def test_sync
    assert(IO.console.sync, "console should be unbuffered")
  ensure
    IO.console(:close)
  end

  def test_getch_timeout
    assert_nil(IO.console.getch(intr: true, time: 0.1, min: 0))
  end

  def test_ttyname
    return unless IO.method_defined?(:ttyname)
    ttyname = IO.console.ttyname
    assert_not_nil(ttyname)
    File.open(ttyname) {|f| assert_predicate(f, :tty?)}
  end

  case
  when Process.respond_to?(:daemon)
    noctty = [EnvUtil.rubybin, "-e", "Process.daemon(true)"]
  when !(rubyw = RbConfig::CONFIG["RUBYW_INSTALL_NAME"]).empty?
    dir, base = File.split(EnvUtil.rubybin)
    noctty = [File.join(dir, base.sub(RUBY_ENGINE, rubyw))]
  else
    rubyw = nil
  end

  if noctty
    require 'tempfile'
    NOCTTY = noctty
    def run_noctty(src)
      t = Tempfile.new("noctty_out")
      t.close
      t2 = Tempfile.new("noctty_run")
      t2.close
      cmd = [*NOCTTY[1..-1],
        TestIO_Console::INCLUDE_OPTS,
        '-e', 'open(ARGV[0], "w") {|f|',
        '-e',   'STDOUT.reopen(f)',
        '-e',   'STDERR.reopen(f)',
        '-e',   'require "io/console"',
        '-e',   "f.puts (#{src}).inspect",
        '-e',   'f.flush',
        '-e',   'File.unlink(ARGV[1])',
        '-e', '}',
        '--', t.path, t2.path]
      assert_ruby_status(cmd, rubybin: NOCTTY[0])
      30.times do
        break unless File.exist?(t2.path)
        sleep 0.1
      end
      t.open
      t.gets.lines(chomp: true)
    ensure
      t.close! if t and !t.closed?
      t2.close!
    end

    def test_noctty
      assert_equal(["[nil, nil]"], run_noctty("[IO.console, IO.console(:tty?)]"))
      if IO.method_defined?(:ttyname)
        assert_equal(["nil"], run_noctty("STDIN.ttyname rescue $!"))
      end
    end
  end
end

defined?(IO.console) and IO.console and IO.console.respond_to?(:pressed?) and \
class TestIO_Console
  def test_pressed_valid
    assert_include([true, false], IO.console.pressed?("HOME"))
    assert_include([true, false], IO.console.pressed?(:"HOME"))
  end

  def test_pressed_invalid
    e = assert_raise(ArgumentError) do
      IO.console.pressed?("HOME\0")
    end
    assert_match(/unknown virtual key code/, e.message)
  end
end

RbConfig::CONFIG["host_os"] =~ /mswin|mingw/ and TestIO_Console.class_eval do
  def test_virtual_key_constants
    {
      VK_TAB: 0x09, VK_RETURN: 0x0d, VK_SHIFT: 0x10,
      VK_CONTROL: 0x11, VK_MENU: 0x12, VK_END: 0x23,
      VK_HOME: 0x24, VK_LEFT: 0x25, VK_UP: 0x26,
      VK_RIGHT: 0x27, VK_DOWN: 0x28, VK_DELETE: 0x2e,
      VK_DIVIDE: 0x6f, VK_LMENU: 0xa4,
      RIGHT_ALT_PRESSED: 0x0001, LEFT_ALT_PRESSED: 0x0002,
      RIGHT_CTRL_PRESSED: 0x0004, LEFT_CTRL_PRESSED: 0x0008,
      SHIFT_PRESSED: 0x0010, NUMLOCK_ON: 0x0020,
      SCROLLLOCK_ON: 0x0040, CAPSLOCK_ON: 0x0080,
      ENHANCED_KEY: 0x0100,
    }.each do |name, value|
      assert_equal(value, IO::Console::Windows.const_get(name, false))
      assert_false(IO::Console.const_defined?(name, false))
    end
  end
end

RbConfig::CONFIG["host_os"] =~ /mswin|mingw/ and defined?(IO.console) and IO.console and \
TestIO_Console.class_eval do
  def test_output_console_mode
    require "fiddle/import"

    kernel32 = Module.new do
      extend Fiddle::Importer
      dlload "kernel32.dll"
      extern "void *CreateFileW(void *, long, long, void *, long, long, void *)"
      extern "int CloseHandle(void *)"
      extern "int GetConsoleMode(void *, void *)"
    end
    File.open("CONOUT$", "r+") do |output|
      path = "CONOUT$\0".encode("UTF-16LE")
      handle = kernel32.CreateFileW(path, -0x40000000, 3, nil, 3, 0, nil)
      buffer = [0].pack("L<")
      assert_not_equal(0, kernel32.GetConsoleMode(handle, buffer))
      original = buffer.unpack1("L<")
      mode = output.console_mode
      begin
        assert_equal((original & 4) != 0, mode.virtual_terminal_processing?)
        assert_equal((original & 2) != 0, mode.wrap_at_eol_output?)

        mode.virtual_terminal_processing = (original & 4) == 0
        mode.wrap_at_eol_output = (original & 2) == 0
        output.console_mode = mode
        assert_not_equal(0, kernel32.GetConsoleMode(handle, buffer))
        assert_equal(original ^ 6, buffer.unpack1("L<"))
      ensure
        mode.virtual_terminal_processing = (original & 4) != 0
        mode.wrap_at_eol_output = (original & 2) != 0
        output.console_mode = mode
        kernel32.CloseHandle(handle)
      end
    end
  rescue LoadError
    pend $!
  end

  def test_cursor_visibility
    require "fiddle/import"

    kernel32 = Module.new do
      extend Fiddle::Importer
      dlload "kernel32.dll"
      extern "void *CreateFileW(void *, long, long, void *, long, long, void *)"
      extern "int CloseHandle(void *)"
      extern "int GetConsoleCursorInfo(void *, void *)"
    end
    File.open("CONOUT$", "r+") do |output|
      info = [0, 0].pack("L<L<")
      path = "CONOUT$\0".encode("UTF-16LE")
      handle = kernel32.CreateFileW(path, -0x40000000, 3, nil, 3, 0, nil)
      assert_not_equal(0, kernel32.GetConsoleCursorInfo(handle, info))
      size, visible = info.unpack("L<L<")
      begin
        assert_same(output, output.hide_cursor)
        assert_not_equal(0, kernel32.GetConsoleCursorInfo(handle, info))
        assert_equal([size, 0], info.unpack("L<L<"))
        assert_same(output, output.show_cursor)
        assert_not_equal(0, kernel32.GetConsoleCursorInfo(handle, info))
        assert_equal([size, 1], info.unpack("L<L<"))
      ensure
        visible == 0 ? output.hide_cursor : output.show_cursor
        kernel32.CloseHandle(handle)
      end
    end
  rescue LoadError
    pend $!
  end

  def test_console_input_events
    require "fiddle"

    kernel32 = Fiddle.dlopen("kernel32.dll")
    create_file = Fiddle::Function.new(
      kernel32["CreateFileW"],
      [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG, Fiddle::TYPE_LONG, Fiddle::TYPE_VOIDP,
       Fiddle::TYPE_LONG, Fiddle::TYPE_LONG, Fiddle::TYPE_VOIDP],
      Fiddle::TYPE_INTPTR_T,
    )
    write_console_input = Fiddle::Function.new(
      kernel32["WriteConsoleInputW"],
      [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG, Fiddle::TYPE_VOIDP],
      Fiddle::TYPE_INT,
    )
    close_handle = Fiddle::Function.new(
      kernel32["CloseHandle"],
      [Fiddle::TYPE_VOIDP],
      Fiddle::TYPE_INT,
    )

    key = [1, 0, 1, 2, 0x41, 0x1e, 0x03a9, 0x18].pack("S<S<L<S<S<S<S<L<")
    resize = [4, 0, 120, 40].pack("S<S<s<s<").ljust(20, "\0")
    mouse = [2, 0, 7, 9, 1, 0x10, 2].pack("S<S<s<s<L<L<L<")
    menu = [8, 0, 123].pack("S<S<L<").ljust(20, "\0")
    focus = [16, 0, 1].pack("S<S<L<").ljust(20, "\0")
    written = [0].pack("L<")
    conin = "CONIN$\0".encode(Encoding::UTF_16LE)
    handle = create_file.call(conin, -0x40000000, 3, nil, 3, 0, nil)
    assert_not_equal(-1, handle)
    begin
      records = key + resize + mouse + menu + focus
      assert_not_equal(0, write_console_input.call(handle, records, 5, written))
      assert_equal(5, written.unpack1("L<"))
      assert_true(IO.console.input_pending?)
      IO.pipe do |read, write|
        assert_false(read.input_pending?)
        write.write("a")
        assert_true(read.input_pending?)
      end
    ensure
      close_handle.call(handle)
    end

    events = IO.console.console_input_events(128)
    index = events.index {|event| event[:type] == :key && event[:unicode_char] == 0x03a9}
    assert_not_nil(index)
    assert_equal(
      [
        {
          type: :key,
          key_down: true,
          repeat_count: 2,
          virtual_key_code: 0x41,
          virtual_scan_code: 0x1e,
          unicode_char: 0x03a9,
          control_key_state: 0x18,
        },
        {type: :window_buffer_size, size: [40, 120]},
        {
          type: :mouse,
          position: [9, 7],
          button_state: 1,
          control_key_state: 0x10,
          event_flags: 2,
        },
        {type: :menu, command_id: 123},
        {type: :focus, set_focus: true},
      ],
      events[index, 5],
    )
    assert_raise(ArgumentError) {IO.console.console_input_events(0)}
    assert_raise(ArgumentError) {IO.console.console_input_events(timeout: -1)}

    assert_equal([], IO.console.console_input_events(128, timeout: 0.01))
    started = Queue.new
    thread = Thread.new do
      Thread.current.report_on_exception = false
      started << true
      IO.console.console_input_events(128, timeout: 100)
    end
    started.pop
    sleep 0.1
    thread.raise(Interrupt)
    assert_raise(Interrupt) {thread.value}
  rescue LoadError
    pend $!
  end

  def test_check_winsize_changed_deprecated
    assert_deprecated_warning(/IO#check_winsize_changed is deprecated/) do
      IO.console.check_winsize_changed {}
    end
  end
end

RUBY_ENGINE == "jruby" && RbConfig::CONFIG["host_os"] =~ /mswin|mingw/ and \
TestIO_Console.class_eval do
  def test_jruby_windows_console_api
    assert(IO::Console::Windows.const_defined?(:Native, false))
    assert_respond_to(STDIN, :console_input_events)
    assert_respond_to(STDIN, :input_pending?)
    assert_respond_to(STDOUT, :console_mode)
    assert_respond_to(STDOUT, :hide_cursor)
    assert_respond_to(STDOUT, :show_cursor)
  end

  def test_jruby_windows_tty_types_are_all_validated
    assert_raise(ArgumentError) {STDOUT.tty?(:any, :unknown)}
    assert_raise(TypeError) {STDOUT.tty?(:any, "msys")}
  end
end

class TestIO_Console
  def test_stringio_getch
    assert_ruby_status %w"--disable=gems -rstringio -rio/console", %q{
      abort unless StringIO.method_defined?(:getch)
    }
    assert_ruby_status %w"--disable=gems -rio/console -rstringio", %q{
      abort unless StringIO.method_defined?(:getch)
    }
    assert_ruby_status %w"--disable=gems -rstringio", %q{
      abort if StringIO.method_defined?(:getch)
    }
  end
end
