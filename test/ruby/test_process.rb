require 'test/unit'
require 'tmpdir'
require_relative 'envutil'

class TestProcess < Test::Unit::TestCase
  def test_rlimit_availability
    begin
      Process.getrlimit(nil)
    rescue NotImplementedError
      assert_raise(NotImplementedError) { Process.setrlimit }
    rescue TypeError
      assert_raise(ArgumentError) { Process.setrlimit }
    end
  end

  def rlimit_exist?
    Process.getrlimit(nil)
  rescue NotImplementedError
    return false
  rescue TypeError
    return true
  end

  def test_rlimit_nofile
    return unless rlimit_exist?
    pid = fork {
      cur_nofile, max_nofile = Process.getrlimit(Process::RLIMIT_NOFILE)
      result = 1
      begin
        Process.setrlimit(Process::RLIMIT_NOFILE, 0, max_nofile)
      rescue Errno::EINVAL
        result = 0
      end
      if result == 1
        begin
          IO.pipe
        rescue Errno::EMFILE
         result = 0
        end
      end
      Process.setrlimit(Process::RLIMIT_NOFILE, cur_nofile, max_nofile)
      exit result
    }
    Process.wait pid
    assert_equal(0, $?.to_i, "#{$?}")
  end

  def test_rlimit_name
    return unless rlimit_exist?
    [
      :AS, "AS",
      :CORE, "CORE",
      :CPU, "CPU",
      :DATA, "DATA",
      :FSIZE, "FSIZE",
      :MEMLOCK, "MEMLOCK",
      :NOFILE, "NOFILE",
      :NPROC, "NPROC",
      :RSS, "RSS",
      :STACK, "STACK",
      :SBSIZE, "SBSIZE",
    ].each {|name|
      if Process.const_defined? "RLIMIT_#{name}"
        assert_nothing_raised { Process.getrlimit(name) }
      else
        assert_raise(ArgumentError) { Process.getrlimit(name) }
      end
    }
    assert_raise(ArgumentError) { Process.getrlimit(:FOO) }
    assert_raise(ArgumentError) { Process.getrlimit("FOO") }
  end

  def test_rlimit_value
    return unless rlimit_exist?
    assert_raise(ArgumentError) { Process.setrlimit(:CORE, :FOO) }
    assert_raise(Errno::EPERM) { Process.setrlimit(:NOFILE, :INFINITY) }
    assert_raise(Errno::EPERM) { Process.setrlimit(:NOFILE, "INFINITY") }
  end

  def with_tmpchdir
    Dir.mktmpdir {|d|
      Dir.chdir(d) {
        yield d
      }
    }
  end

  def test_execopts_opts
    assert_nothing_raised {
      Process.wait Process.spawn("true", {})
    }
    assert_raise(ArgumentError) {
      Process.wait Process.spawn("true", :foo => 100)
    }
    assert_raise(ArgumentError) {
      Process.wait Process.spawn("true", Process => 100)
    }
  end

  def test_execopts_pgroup
    ruby = EnvUtil.rubybin
    assert_nothing_raised { system("true", :pgroup=>false) }

    io = IO.popen([ruby, "-e", "print Process.getpgrp"])
    assert_equal(Process.getpgrp.to_s, io.read)
    io.close

    io = IO.popen([ruby, "-e", "print Process.getpgrp", :pgroup=>true])
    assert_equal(io.pid.to_s, io.read)
    io.close

    assert_raise(ArgumentError) { system("true", :pgroup=>-1) }
    assert_raise(Errno::EPERM) { Process.wait spawn("true", :pgroup=>1) }

    io1 = IO.popen([ruby, "-e", "print Process.getpgrp", :pgroup=>true])
    io2 = IO.popen([ruby, "-e", "print Process.getpgrp", :pgroup=>io1.pid])
    assert_equal(io1.pid.to_s, io1.read)
    assert_equal(io1.pid.to_s, io2.read)
    Process.wait io1.pid
    Process.wait io2.pid
    io1.close
    io2.close

  end

  def test_execopts_rlimit
    return unless rlimit_exist?
    assert_raise(ArgumentError) { system("true", :rlimit_foo=>0) }
    assert_raise(ArgumentError) { system("true", :rlimit_NOFILE=>0) }
    assert_raise(ArgumentError) { system("true", :rlimit_nofile=>[]) }
    assert_raise(ArgumentError) { system("true", :rlimit_nofile=>[1,2,3]) }

    max = Process.getrlimit(:CORE).last

    n = max
    IO.popen([EnvUtil.rubybin, "-e",
             "p Process.getrlimit(:CORE)", :rlimit_core=>n]) {|io|
      assert_equal("[#{n}, #{n}]\n", io.read)
    }

    n = 0
    IO.popen([EnvUtil.rubybin, "-e",
             "p Process.getrlimit(:CORE)", :rlimit_core=>n]) {|io|
      assert_equal("[#{n}, #{n}]\n", io.read)
    }

    n = max
    IO.popen([EnvUtil.rubybin, "-e",
             "p Process.getrlimit(:CORE)", :rlimit_core=>[n]]) {|io|
      assert_equal("[#{n}, #{n}]", io.read.chomp)
    }

    m, n = 0, max
    IO.popen([EnvUtil.rubybin, "-e",
             "p Process.getrlimit(:CORE)", :rlimit_core=>[m,n]]) {|io|
      assert_equal("[#{m}, #{n}]", io.read.chomp)
    }

    m, n = 0, 0
    IO.popen([EnvUtil.rubybin, "-e",
             "p Process.getrlimit(:CORE)", :rlimit_core=>[m,n]]) {|io|
      assert_equal("[#{m}, #{n}]", io.read.chomp)
    }

    n = max
    IO.popen([EnvUtil.rubybin, "-e",
      "p Process.getrlimit(:CORE), Process.getrlimit(:CPU)",
      :rlimit_core=>n, :rlimit_cpu=>3600]) {|io|
      assert_equal("[#{n}, #{n}]\n[3600, 3600]", io.read.chomp)
    }
  end

  def test_execopts_env
    assert_raise(ArgumentError) {
      system({"F=O"=>"BAR"}, "env")
    }

    h = {}
    ENV.each {|k,v| h[k] = nil unless k == "PATH" }
    IO.popen([h, "env"]) {|io|
      assert_equal(1, io.readlines.length)
    }

    IO.popen([{"FOO"=>"BAR"}, "env"]) {|io|
      assert_match(/FOO=BAR/, io.read)
    }

    with_tmpchdir {|d|
      system({"fofo"=>"haha"}, "env", STDOUT=>"out")
      assert_match(/fofo=haha/, File.read("out").chomp)
    }
  end

  def test_execopts_unsetenv_others
    IO.popen(["/usr/bin/env", :unsetenv_others=>true]) {|io|
      assert_equal("", io.read)
    }
    IO.popen([{"A"=>"B"}, "/usr/bin/env", :unsetenv_others=>true]) {|io|
      assert_equal("A=B\n", io.read)
    }
  end

  def test_execopts_chdir
    with_tmpchdir {|d|
      Process.wait Process.spawn("pwd > dir", :chdir => d)
      assert_equal(d, File.read("#{d}/dir").chomp)
      assert_raise(Errno::ENOENT) {
        Process.wait Process.spawn("true", :chdir => "d/notexist")
      }
    }
  end

  def test_execopts_umask
    with_tmpchdir {|d|
      n = "#{d}/mask"
      Process.wait Process.spawn("sh -c umask > #{n}", :umask => 0)
      assert_equal("0000", File.read(n).chomp)
      Process.wait Process.spawn("sh -c umask > #{n}", :umask => 0777)
      assert_equal("0777", File.read(n).chomp)
    }
  end

  def with_pipe
    begin
      r, w = IO.pipe
      yield r, w
    ensure
      r.close unless r.closed?
      w.close unless w.closed?
    end
  end

  def with_pipes(n)
    ary = []
    begin
      n.times {
        ary << IO.pipe
      }
      yield ary
    ensure
      ary.each {|r, w|
        r.close unless r.closed?
        w.close unless w.closed?
      }
    end
  end

  def test_execopts_redirect
    with_tmpchdir {|d|
      Process.wait Process.spawn("echo a", STDOUT=>["out", File::WRONLY|File::CREAT|File::TRUNC, 0644])
      assert_equal("a", File.read("out").chomp)
      Process.wait Process.spawn("echo 0", STDOUT=>["out", File::WRONLY|File::CREAT|File::APPEND, 0644])
      assert_equal("a\n0\n", File.read("out"))
      Process.wait Process.spawn("sort", STDIN=>["out", File::RDONLY, 0644],
                                         STDOUT=>["out2", File::WRONLY|File::CREAT|File::TRUNC, 0644])
      assert_equal("0\na\n", File.read("out2"))
      Process.wait Process.spawn("echo b", [STDOUT, STDERR]=>["out", File::WRONLY|File::CREAT|File::TRUNC, 0644])
      assert_equal("b", File.read("out").chomp)
      Process.wait Process.spawn("echo a", STDOUT=>:close, STDERR=>["out", File::WRONLY|File::CREAT|File::TRUNC, 0644])
      #p File.read("out")
      assert(!File.read("out").empty?) # error message such as "echo: write error: Bad file descriptor\n".
      Process.wait Process.spawn("echo c", STDERR=>STDOUT, STDOUT=>["out", File::WRONLY|File::CREAT|File::TRUNC, 0644])
      assert_equal("c", File.read("out").chomp)
      File.open("out", "w") {|f|
        Process.wait Process.spawn("echo d", f=>STDOUT, STDOUT=>f)
        assert_equal("d", File.read("out").chomp)
      }
      Process.wait Process.spawn("echo e", STDOUT=>["out", File::WRONLY|File::CREAT|File::TRUNC, 0644],
                                 3=>STDOUT, 4=>STDOUT, 5=>STDOUT, 6=>STDOUT, 7=>STDOUT)
      assert_equal("e", File.read("out").chomp)
      File.open("out", "w") {|f|
        h = {STDOUT=>f, f=>STDOUT}
        3.upto(30) {|i| h[i] = STDOUT if f.fileno != i }
        Process.wait Process.spawn("echo f", h)
        assert_equal("f", File.read("out").chomp)
      }
      assert_raise(ArgumentError) {
        Process.wait Process.spawn("echo f", 1=>Process)
      }
      assert_raise(ArgumentError) {
        Process.wait Process.spawn("echo f", [Process]=>1)
      }
      assert_raise(ArgumentError) {
        Process.wait Process.spawn("echo f", [1, STDOUT]=>2)
      }
      assert_raise(ArgumentError) {
        Process.wait Process.spawn("echo f", -1=>2)
      }
      Process.wait Process.spawn("echo hhh; echo ggg", STDOUT=>"out")
      assert_equal("hhh\nggg\n", File.read("out"))
      Process.wait Process.spawn("sort", STDIN=>"out", STDOUT=>"out2")
      assert_equal("ggg\nhhh\n", File.read("out2"))

      assert_raise(Errno::ENOENT) {
        Process.wait Process.spawn("non-existing-command", (3..100).to_a=>["err", File::WRONLY|File::CREAT])
      }
      assert_equal("", File.read("err"))

      system("echo bb; echo aa", STDOUT=>["out", "w"])
      assert_equal("bb\naa\n", File.read("out"))
      system("sort", STDIN=>["out"], STDOUT=>"out2")
      assert_equal("aa\nbb\n", File.read("out2"))

      with_pipe {|r1, w1|
        with_pipe {|r2, w2|
          pid = spawn("sort", STDIN=>r1, STDOUT=>w2, w1=>:close, r2=>:close)
          r1.close
          w2.close
          w1.puts "c"
          w1.puts "a"
          w1.puts "b"
          w1.close
          assert_equal("a\nb\nc\n", r2.read)
        }
      }

      with_pipes(5) {|pipes|
        ios = pipes.flatten
        h = {}
        ios.length.times {|i| h[ios[i]] = ios[(i-1)%ios.length] }
        h2 = h.invert
        rios = pipes.map {|r, w| r }
        wios = pipes.map {|r, w| w }
        child_wfds = wios.map {|w| h2[w].fileno }
        pid = spawn(EnvUtil.rubybin, "-e",
                "[#{child_wfds.join(',')}].each {|fd| IO.new(fd).puts fd }", h)
        pipes.each {|r, w|
          assert_equal("#{h2[w].fileno}\n", r.gets)
        }
        Process.wait pid;
      }

      with_pipes(5) {|pipes|
        ios = pipes.flatten
        h = {}
        ios.length.times {|i| h[ios[i]] = ios[(i+1)%ios.length] }
        h2 = h.invert
        rios = pipes.map {|r, w| r }
        wios = pipes.map {|r, w| w }
        child_wfds = wios.map {|w| h2[w].fileno }
        pid = spawn(EnvUtil.rubybin, "-e",
                "[#{child_wfds.join(',')}].each {|fd| IO.new(fd).puts fd }", h)
        pipes.each {|r, w|
          assert_equal("#{h2[w].fileno}\n", r.gets)
        }
        Process.wait pid;
      }

      closed_fd = nil
      with_pipes(5) {|pipes|
        io = pipes.last.last
        closed_fd = io.fileno
      }
      assert_raise(Errno::EBADF) { Process.wait spawn("true", closed_fd=>closed_fd) }

      with_pipe {|r, w|
        w.close_on_exec = true
        pid = spawn(EnvUtil.rubybin, "-e", "IO.new(#{w.fileno}).print 'a'", w=>w)
        w.close
        assert_equal("a", r.read)
        Process.wait pid
      }

      system("echo funya", :out=>"out")
      assert_equal("funya\n", File.read("out"))
      system("echo henya 1>&2", :err=>"out")
      assert_equal("henya\n", File.read("out"))
      IO.popen(["cat", :in=>"out"]) {|io|
        assert_equal("henya\n", io.read)
      }
    }
  end

  def test_execopts_exec
    with_tmpchdir {|d|
      pid = fork {
        exec "echo aaa", STDOUT=>"foo"
      }
      Process.wait pid
      assert_equal("aaa\n", File.read("foo"))
    }
  end

  def test_execopts_popen
    with_tmpchdir {|d|
      IO.popen("echo foo") {|io| assert_equal("foo\n", io.read) }
      assert_raise(Errno::ENOENT) { IO.popen(["echo bar"]) {} }
      IO.popen(["echo", "baz"]) {|io| assert_equal("baz\n", io.read) }
      #IO.popen(["echo", "qux", STDOUT=>STDOUT]) {|io| assert_equal("qux\n", io.read) }
      IO.popen(["echo", "hoge", STDERR=>STDOUT]) {|io|
        assert_equal("hoge\n", io.read)
      }
      #IO.popen(["echo", "fuga", STDOUT=>"out"]) {|io|
      #  assert_equal("", io.read)
      #}
      #assert_equal("fuga\n", File.read("out"))
      #IO.popen(["sh", "-c", "echo a >&3", 3=>STDOUT]) {|io|
      #  assert_equal("a\n", io.read)
      #}
      IO.popen(["sh", "-c", "echo b >&9",
               9=>["out2", File::WRONLY|File::CREAT|File::TRUNC]]) {|io|
        assert_equal("", io.read)
      }
      assert_equal("b\n", File.read("out2"))
      IO.popen("-") {|io|
        if !io
          puts "fooo"
        else
          assert_equal("fooo\n", io.read)
        end
      }
    }
  end

  def test_fd_inheritance
    with_pipe {|r, w|
      system("echo ba >&#{w.fileno}")
      w.close
      assert_equal("ba\n", r.read)
    }
    with_pipe {|r, w|
      Process.wait spawn("exec 2>/dev/null; echo bi >&#{w.fileno}")
      w.close
      assert_equal("", r.read)
    }
    with_pipe {|r, w|
      Process.wait fork { exec("echo bu >&#{w.fileno}") }
      w.close
      assert_equal("bu\n", r.read)
    }
    with_pipe {|r, w|
      io = IO.popen("echo be 2>&1 >&#{w.fileno}")
      w.close
      errmsg = io.read
      assert_equal("", r.read)
      assert_not_equal("", errmsg)
    }
    with_pipe {|r, w|
      io = IO.popen([EnvUtil.rubybin, "-e", "STDERR.reopen(STDOUT); IO.new(#{w.fileno}).puts('me')"])
      w.close
      errmsg = io.read
      assert_equal("", r.read)
      assert_not_equal("", errmsg)
    }
    with_pipe {|r, w|
      errmsg = `echo bo 2>&1 >&#{w.fileno}`
      w.close
      assert_equal("", r.read)
      assert_not_equal("", errmsg)
    }
  end

  def test_execopts_close_others
    with_tmpchdir {|d|
      with_pipe {|r, w|
        system("exec >/dev/null 2>err; echo ma >&#{w.fileno}", :close_others=>true)
        w.close
        assert_equal("", r.read)
        File.unlink("err")
      }
      with_pipe {|r, w|
        Process.wait spawn("exec >/dev/null 2>err; echo mi >&#{w.fileno}", :close_others=>true)
        w.close
        assert_equal("", r.read)
        File.unlink("err")
      }
      with_pipe {|r, w|
        Process.wait spawn("echo bi >&#{w.fileno}", :close_others=>false)
        w.close
        assert_equal("bi\n", r.read)
      }
      with_pipe {|r, w|
        Process.wait fork { exec("exec >/dev/null 2>err; echo mu >&#{w.fileno}", :close_others=>true) }
        w.close
        assert_equal("", r.read)
        File.unlink("err")
      }
      with_pipe {|r, w|
        io = IO.popen([EnvUtil.rubybin, "-e", "STDERR.reopen(STDOUT); IO.new(#{w.fileno}).puts('me')", :close_others=>true])
        w.close
        errmsg = io.read
        assert_equal("", r.read)
        assert_not_equal("", errmsg)
      }
      with_pipe {|r, w|
        io = IO.popen([EnvUtil.rubybin, "-e", "STDERR.reopen(STDOUT); IO.new(#{w.fileno}).puts('mo')", :close_others=>false])
        w.close
        errmsg = io.read
        assert_equal("mo\n", r.read)
        assert_equal("", errmsg)
      }
      with_pipe {|r, w|
        io = IO.popen([EnvUtil.rubybin, "-e", "STDERR.reopen(STDOUT); IO.new(#{w.fileno}).puts('mo')", :close_others=>nil])
        w.close
        errmsg = io.read
        assert_equal("mo\n", r.read)
        assert_equal("", errmsg)
      }

    }
  end

  def test_execopts_modification
    h = {}
    Process.wait spawn(EnvUtil.rubybin, '-e', '', h)
    assert_equal({}, h)

    h = {}
    system(EnvUtil.rubybin, '-e', '', h)
    assert_equal({}, h)

    h = {}
    io = IO.popen([EnvUtil.rubybin, '-e', '', h])
    io.close
    assert_equal({}, h)
  end

  def test_system
    str = "echo fofo"
    assert_nil(system([str, str]))
  end

end
