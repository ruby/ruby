# frozen_string_literal: false
begin
  require 'io/console'
  require 'test/unit'
  require 'pty'
rescue LoadError
end

class TestIO_Console < Test::Unit::TestCase
  PATHS = $LOADED_FEATURES.grep(%r"/io/console(?:\.#{RbConfig::CONFIG['DLEXT']}|/\w+\.rb)\z") {$`}
  PATHS.uniq!

  # FreeBSD seems to hang on TTOU when running parallel tests
  # tested on FreeBSD 11.x.
  #
  # Solaris gets stuck too, even in non-parallel mode.
  # It occurs only in chkbuild.  It does not occur when running
  # `make test-all` in SSH terminal.
  #
  # I suspect that it occurs only when having no TTY.
  # (Parallel mode runs tests in child processes, so I guess
  # they has no TTY.)
  # But it does not occur in `make test-all > /dev/null`, so
  # there should be an additional factor, I guess.
  def set_winsize_setup
    @old_ttou = trap(:TTOU, 'IGNORE') if RUBY_PLATFORM =~ /freebsd|solaris/i
  end

  def set_winsize_teardown
    trap(:TTOU, @old_ttou) if defined?(@old_ttou) and @old_ttou
  end
end

defined?(PTY) and defined?(IO.console) and TestIO_Console.class_eval do
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
	sleep 0.1
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

  def test_getpass
    skip unless IO.method_defined?("getpass")
    run_pty("p IO.console.getpass('> ')") do |r, w|
      assert_equal("> ", r.readpartial(10))
      sleep 0.1
      w.print "asdf\n"
      sleep 0.1
      assert_equal("\r\n", r.gets)
      assert_equal("\"asdf\"", r.gets.chomp)
    end
  end

  def test_iflush
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
      end;
      assert_equal("\e[6n", r.readpartial(5))
      w.print("\e[12;34R"); w.flush
      assert_equal([11, 33], eval(r.gets))
      assert_equal("\e[3B", r.gets.chomp)
      assert_equal("\e[4C", r.gets.chomp)
      assert_equal("\e[2D", r.gets.chomp)
      assert_equal("\e[1A", r.gets.chomp)
    end
  end

  def assert_ctrl(expect, cc, r, w)
    sleep 0.1
    w.print cc
    w.flush
    result = EnvUtil.timeout(3) {r.gets}
    assert_equal(expect, result.chomp)
  end

  def test_intr
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
        assert_ctrl("Interrupt", cc, r, w) unless /linux/ =~ RUBY_PLATFORM
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

    def test_sync
      assert_equal(["true"], run_pty("p IO.console.sync"))
    end
  end

  private
  def helper
    m, s = PTY.open
  rescue RuntimeError
    skip $!
  else
    yield m, s
  ensure
    m.close if m
    s.close if s
  end

  def run_pty(src, n = 1)
    r, w, pid = PTY.spawn(EnvUtil.rubybin, "-I#{TestIO_Console::PATHS.join(File::PATH_SEPARATOR)}", "-rio/console", "-e", src)
  rescue RuntimeError
    skip $!
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

defined?(IO.console) and TestIO_Console.class_eval do
  if IO.console
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
      IO.console.winsize = [s[0], s[1]+1]
      assert_equal([s[0], s[1]+1], IO.console.winsize, bug)
      IO.console.winsize = s
      assert_equal(s, IO.console.winsize, bug)
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

    def test_sync
      assert(IO.console.sync, "console should be unbuffered")
    ensure
      IO.console(:close)
    end
  end
end

defined?(IO.console) and TestIO_Console.class_eval do
  case
  when Process.respond_to?(:daemon)
    noctty = [EnvUtil.rubybin, "-e", "Process.daemon(true)"]
  when !(rubyw = RbConfig::CONFIG["RUBYW_INSTALL_NAME"]).empty?
    dir, base = File.split(EnvUtil.rubybin)
    noctty = [File.join(dir, base.sub(RUBY_ENGINE, rubyw))]
  end

  if noctty
    require 'tempfile'
    NOCTTY = noctty
    def test_noctty
      t = Tempfile.new("noctty_out")
      t.close
      t2 = Tempfile.new("noctty_run")
      t2.close
      cmd = [*NOCTTY[1..-1],
        '-e', 'open(ARGV[0], "w") {|f|',
        '-e',   'STDOUT.reopen(f)',
        '-e',   'STDERR.reopen(f)',
        '-e',   'require "io/console"',
        '-e',   'f.puts IO.console.inspect',
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
      assert_equal("nil", t.gets(nil).chomp)
    ensure
      t.close! if t and !t.closed?
      t2.close!
    end
  end
end

defined?(IO.console) and IO.console and IO.console.respond_to?(:pressed?) and
  TestIO_Console.class_eval do
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

TestIO_Console.class_eval do
  def test_stringio_getch
    assert_separately %w"--disable=gems -rstringio -rio/console", %q{
      assert_operator(StringIO, :method_defined?, :getch)
    }
    assert_separately %w"--disable=gems -rio/console -rstringio", %q{
      assert_operator(StringIO, :method_defined?, :getch)
    }
    assert_separately %w"--disable=gems -rstringio", %q{
      assert_not_operator(StringIO, :method_defined?, :getch)
    }
  end
end
