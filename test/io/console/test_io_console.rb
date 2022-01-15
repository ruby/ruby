# frozen_string_literal: false
begin
  require 'io/console'
  require 'test/unit'
  require 'pty'
rescue LoadError
end

class TestIO_Console < Test::Unit::TestCase
  begin
    PATHS = $LOADED_FEATURES.grep(%r"/io/console(?:\.#{RbConfig::CONFIG['DLEXT']}|\.rb|/\w+\.rb)\z") {$`}
  rescue Encoding::CompatibilityError
    $stderr.puts "test_io_console.rb debug"
    $LOADED_FEATURES.each{|path| $stderr.puts [path, path.encoding].inspect}
    raise
  end
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

  def test_failed_path
    exceptions = %w[ENODEV ENOTTY EBADF ENXIO].map {|e|
      Errno.const_get(e) if Errno.const_defined?(e)
    }
    exceptions.compact!
    omit if exceptions.empty?
    File.open(IO::NULL) do |f|
      e = assert_raise(*exceptions) do
        f.echo?
      end
      assert_include(e.message, IO::NULL)
    end
  end
end

defined?(PTY) and defined?(IO.console) and TestIO_Console.class_eval do
  Bug6116 = '[ruby-dev:45309]'

  def test_raw
    helper {|controller, worker|
      worker.print "abc\n"
      assert_equal("abc\r\n", controller.gets)
      assert_send([worker, :echo?])
      worker.raw {
        assert_not_send([worker, :echo?], Bug6116)
        worker.print "def\n"
        assert_equal("def\n", controller.gets)
      }
      assert_send([worker, :echo?])
      worker.print "ghi\n"
      assert_equal("ghi\r\n", controller.gets)
    }
  end

  def test_raw_minchar
    q = Thread::Queue.new
    helper {|controller, worker|
      len = 0
      assert_equal([nil, 0], [worker.getch(min: 0), len])
      main = Thread.current
      go = false
      th = Thread.start {
        q.pop
        sleep 0.01 until main.stop?
        len += 1
        controller.print("a")
        controller.flush
        sleep 0.01 until go and main.stop?
        len += 10
        controller.print("1234567890")
        controller.flush
      }
      begin
        sleep 0.1
        q.push(1)
        assert_equal(["a", 1], [worker.getch(min: 1), len])
        go = true
        assert_equal(["1", 11], [worker.getch, len])
      ensure
        th.join
      end
    }
  end

  def test_raw_timeout
    helper {|controller, worker|
      len = 0
      assert_equal([nil, 0], [worker.getch(min: 0, time: 0.1), len])
      main = Thread.current
      th = Thread.start {
        sleep 0.01 until main.stop?
        len += 2
        controller.print("ab")
      }
      begin
        assert_equal(["a", 2], [worker.getch(min: 1, time: 1), len])
        assert_equal(["b", 2], [worker.getch(time: 1), len])
      ensure
        th.join
      end
    }
  end

  def test_raw!
    helper {|controller, worker|
      worker.raw!
      worker.print "foo\n"
      assert_equal("foo\n", controller.gets)
    }
  end

  def test_cooked
    helper {|controller, worker|
      assert_send([worker, :echo?])
      worker.raw {
        worker.print "abc\n"
        assert_equal("abc\n", controller.gets)
        assert_not_send([worker, :echo?], Bug6116)
        worker.cooked {
          assert_send([worker, :echo?])
          worker.print "def\n"
          assert_equal("def\r\n", controller.gets)
        }
        assert_not_send([worker, :echo?], Bug6116)
      }
      assert_send([worker, :echo?])
      worker.print "ghi\n"
      assert_equal("ghi\r\n", controller.gets)
    }
  end

  def test_echo
    helper {|controller, worker|
      assert_send([worker, :echo?])
      controller.print "a"
      assert_equal("a", controller.readpartial(10))
    }
  end

  def test_noecho
    helper {|controller, worker|
      worker.noecho {
	assert_not_send([worker, :echo?])
	controller.print "a"
	sleep 0.1
      }
      controller.print "b"
      assert_equal("b", controller.readpartial(10))
    }
  end

  def test_noecho2
    helper {|controller, worker|
      assert_send([worker, :echo?])
      controller.print "a\n"
      sleep 0.1
      worker.print "b\n"
      sleep 0.1
      assert_equal("a\r\nb\r\n", controller.gets + controller.gets)
      assert_equal("a\n", worker.gets)
      worker.noecho {
        assert_not_send([worker, :echo?])
        controller.print "a\n"
        worker.print "b\n"
        assert_equal("b\r\n", controller.gets)
        assert_equal("a\n", worker.gets)
      }
      assert_send([worker, :echo?])
      controller.print "a\n"
      sleep 0.1
      worker.print "b\n"
      sleep 0.1
      assert_equal("a\r\nb\r\n", controller.gets + controller.gets)
      assert_equal("a\n", worker.gets)
    }
  end

  def test_setecho
    helper {|controller, worker|
      assert_send([worker, :echo?])
      worker.echo = false
      controller.print "a"
      sleep 0.1
      worker.echo = true
      controller.print "b"
      assert_equal("b", controller.readpartial(10))
    }
  end

  def test_setecho2
    helper {|controller, worker|
      assert_send([worker, :echo?])
      controller.print "a\n"
      sleep 0.1
      worker.print "b\n"
      sleep 0.1
      assert_equal("a\r\nb\r\n", controller.gets + controller.gets)
      assert_equal("a\n", worker.gets)
      worker.echo = false
      assert_not_send([worker, :echo?])
      controller.print "a\n"
      worker.print "b\n"
      assert_equal("b\r\n", controller.gets)
      assert_equal("a\n", worker.gets)
      worker.echo = true
      assert_send([worker, :echo?])
      controller.print "a\n"
      sleep 0.1
      worker.print "b\n"
      sleep 0.1
      assert_equal("a\r\nb\r\n", controller.gets + controller.gets)
      assert_equal("a\n", worker.gets)
    }
  end

  def test_getpass
    omit unless IO.method_defined?("getpass")
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
  end

  def test_iflush
    helper {|controller, worker|
      controller.print "a"
      worker.iflush
      controller.print "b\n"
      controller.flush
      assert_equal("b\n", worker.gets)
    }
  end

  def test_oflush
    helper {|controller, worker|
      worker.print "a"
      worker.oflush # oflush may be issued after "a" is already sent.
      worker.print "b"
      worker.flush
      sleep 0.1
      assert_include(["b", "ab"], controller.readpartial(10))
    }
  end

  def test_ioflush
    helper {|controller, worker|
      controller.print "a"
      worker.ioflush
      controller.print "b\n"
      controller.flush
      assert_equal("b\n", worker.gets)
    }
  end

  def test_ioflush2
    helper {|controller, worker|
      worker.print "a"
      worker.ioflush # ioflush may be issued after "a" is already sent.
      worker.print "b"
      worker.flush
      sleep 0.1
      assert_include(["b", "ab"], controller.readpartial(10))
    }
  end

  def test_winsize
    helper {|controller, worker|
      begin
        assert_equal([0, 0], worker.winsize)
      rescue Errno::EINVAL # OpenSolaris 2009.06 TIOCGWINSZ causes Errno::EINVAL before TIOCSWINSZ.
      else
        assert_equal([80, 25], worker.winsize = [80, 25])
        assert_equal([80, 25], worker.winsize)
        #assert_equal([80, 25], controller.winsize)
        assert_equal([100, 40], controller.winsize = [100, 40])
        #assert_equal([100, 40], worker.winsize)
        assert_equal([100, 40], controller.winsize)
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
        assert_ctrl("Interrupt", cc, r, w) unless /linux|solaris/ =~ RUBY_PLATFORM
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
  end

  private
  def helper
    controller, worker = PTY.open
  rescue RuntimeError
    omit $!
  else
    yield controller, worker
  ensure
    controller.close if controller
    worker.close if worker
  end

  def run_pty(src, n = 1)
    pend("PTY.spawn cannot control terminal on JRuby") if RUBY_ENGINE == 'jruby'

    r, w, pid = PTY.spawn(EnvUtil.rubybin, "-I#{TestIO_Console::PATHS.join(File::PATH_SEPARATOR)}", "-rio/console", "-e", src)
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
