# coding: utf-8
# frozen_string_literal: false
require 'test/unit'
require 'tempfile'
require 'timeout'
require 'io/wait'
require 'rbconfig'

class TestProcess < Test::Unit::TestCase
  RUBY = EnvUtil.rubybin

  def setup
    Process.waitall
  end

  def teardown
    Process.waitall
  end

  def windows?
    self.class.windows?
  end
  def self.windows?
    return /mswin|mingw|bccwin/ =~ RUBY_PLATFORM
  end

  def write_file(filename, content)
    File.open(filename, "w") {|f|
      f << content
    }
  end

  def with_tmpchdir
    Dir.mktmpdir {|d|
      d = File.realpath(d)
      Dir.chdir(d) {
        yield d
      }
    }
  end

  def run_in_child(str) # should be called in a temporary directory
    write_file("test-script", str)
    Process.wait spawn(RUBY, "test-script")
    $?
  end

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
    with_tmpchdir {
      write_file 's', <<-"End"
        # Too small RLIMIT_NOFILE, such as zero, causes problems.
        # [OpenBSD] Setting to zero freezes this test.
        # [GNU/Linux] EINVAL on poll().  EINVAL on ruby's internal poll() ruby with "[ASYNC BUG] thread_timer: select".
        pipes = IO.pipe
	limit = pipes.map {|io| io.fileno }.min
	result = 1
	begin
	  Process.setrlimit(Process::RLIMIT_NOFILE, limit)
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
	exit result
      End
      pid = spawn RUBY, "s"
      Process.wait pid
      assert_equal(0, $?.to_i, "#{$?}")
    }
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
      :MSGQUEUE, "MSGQUEUE",
      :NICE, "NICE",
      :NOFILE, "NOFILE",
      :NPROC, "NPROC",
      :RSS, "RSS",
      :RTPRIO, "RTPRIO",
      :RTTIME, "RTTIME",
      :SBSIZE, "SBSIZE",
      :SIGPENDING, "SIGPENDING",
      :STACK, "STACK",
    ].each {|name|
      if Process.const_defined? "RLIMIT_#{name}"
        assert_nothing_raised { Process.getrlimit(name) }
      else
        assert_raise(ArgumentError) { Process.getrlimit(name) }
      end
    }
    assert_raise(ArgumentError) { Process.getrlimit(:FOO) }
    assert_raise(ArgumentError) { Process.getrlimit("FOO") }
    assert_raise_with_message(ArgumentError, /\u{30eb 30d3 30fc}/) { Process.getrlimit("\u{30eb 30d3 30fc}") }
  end

  def test_rlimit_value
    return unless rlimit_exist?
    assert_raise(ArgumentError) { Process.setrlimit(:FOO, 0) }
    assert_raise(ArgumentError) { Process.setrlimit(:CORE, :FOO) }
    assert_raise_with_message(ArgumentError, /\u{30eb 30d3 30fc}/) { Process.setrlimit("\u{30eb 30d3 30fc}", 0) }
    assert_raise_with_message(ArgumentError, /\u{30eb 30d3 30fc}/) { Process.setrlimit(:CORE, "\u{30eb 30d3 30fc}") }
    with_tmpchdir do
      s = run_in_child(<<-'End')
        cur, max = Process.getrlimit(:NOFILE)
        Process.setrlimit(:NOFILE, [max-10, cur].min)
        begin
          Process.setrlimit(:NOFILE, :INFINITY)
        rescue Errno::EPERM
          exit false
        end
      End
      assert_not_predicate(s, :success?)
      s = run_in_child(<<-'End')
        cur, max = Process.getrlimit(:NOFILE)
        Process.setrlimit(:NOFILE, [max-10, cur].min)
        begin
          Process.setrlimit(:NOFILE, "INFINITY")
        rescue Errno::EPERM
          exit false
        end
      End
      assert_not_predicate(s, :success?)
    end
  end

  TRUECOMMAND = [RUBY, '-e', '']

  def test_execopts_opts
    assert_nothing_raised {
      Process.wait Process.spawn(*TRUECOMMAND, {})
    }
    assert_raise(ArgumentError) {
      Process.wait Process.spawn(*TRUECOMMAND, :foo => 100)
    }
    assert_raise(ArgumentError) {
      Process.wait Process.spawn(*TRUECOMMAND, Process => 100)
    }
  end

  def test_execopts_pgroup
    skip "system(:pgroup) is not supported" if windows?
    assert_nothing_raised { system(*TRUECOMMAND, :pgroup=>false) }

    io = IO.popen([RUBY, "-e", "print Process.getpgrp"])
    assert_equal(Process.getpgrp.to_s, io.read)
    io.close

    io = IO.popen([RUBY, "-e", "print Process.getpgrp", :pgroup=>true])
    assert_equal(io.pid.to_s, io.read)
    io.close

    assert_raise(ArgumentError) { system(*TRUECOMMAND, :pgroup=>-1) }
    IO.popen([RUBY, '-egets'], 'w') do |f|
      assert_raise(Errno::EPERM) {
        Process.wait spawn(*TRUECOMMAND, :pgroup=>f.pid)
      }
    end

    io1 = IO.popen([RUBY, "-e", "print Process.getpgrp", :pgroup=>true])
    io2 = IO.popen([RUBY, "-e", "print Process.getpgrp", :pgroup=>io1.pid])
    assert_equal(io1.pid.to_s, io1.read)
    assert_equal(io1.pid.to_s, io2.read)
    Process.wait io1.pid
    Process.wait io2.pid
    io1.close
    io2.close
  end

  def test_execopts_rlimit
    return unless rlimit_exist?
    assert_raise(ArgumentError) { system(*TRUECOMMAND, :rlimit_foo=>0) }
    assert_raise(ArgumentError) { system(*TRUECOMMAND, :rlimit_NOFILE=>0) }
    assert_raise(ArgumentError) { system(*TRUECOMMAND, :rlimit_nofile=>[]) }
    assert_raise(ArgumentError) { system(*TRUECOMMAND, :rlimit_nofile=>[1,2,3]) }

    max = Process.getrlimit(:CORE).last

    n = max
    IO.popen([RUBY, "-e",
             "p Process.getrlimit(:CORE)", :rlimit_core=>n]) {|io|
      assert_equal("[#{n}, #{n}]\n", io.read)
    }

    n = 0
    IO.popen([RUBY, "-e",
             "p Process.getrlimit(:CORE)", :rlimit_core=>n]) {|io|
      assert_equal("[#{n}, #{n}]\n", io.read)
    }

    n = max
    IO.popen([RUBY, "-e",
             "p Process.getrlimit(:CORE)", :rlimit_core=>[n]]) {|io|
      assert_equal("[#{n}, #{n}]", io.read.chomp)
    }

    m, n = 0, max
    IO.popen([RUBY, "-e",
             "p Process.getrlimit(:CORE)", :rlimit_core=>[m,n]]) {|io|
      assert_equal("[#{m}, #{n}]", io.read.chomp)
    }

    m, n = 0, 0
    IO.popen([RUBY, "-e",
             "p Process.getrlimit(:CORE)", :rlimit_core=>[m,n]]) {|io|
      assert_equal("[#{m}, #{n}]", io.read.chomp)
    }

    n = max
    IO.popen([RUBY, "-e",
      "p Process.getrlimit(:CORE), Process.getrlimit(:CPU)",
      :rlimit_core=>n, :rlimit_cpu=>3600]) {|io|
      assert_equal("[#{n}, #{n}]\n[3600, 3600]", io.read.chomp)
    }

    assert_raise(ArgumentError) do
      system(RUBY, '-e', 'exit',  'rlimit_bogus'.to_sym => 123)
    end
    assert_separately([],"#{<<~"begin;"}\n#{<<~'end;'}", 'rlimit_cpu'.to_sym => 3600)
    BUG = "[ruby-core:82033] [Bug #13744]"
    begin;
      assert_equal([3600,3600], Process.getrlimit(:CPU), BUG)
    end;

    assert_raise_with_message(ArgumentError, /bogus/) do
      system(RUBY, '-e', 'exit', :rlimit_bogus => 123)
    end

    assert_raise_with_message(ArgumentError, /rlimit_cpu/) {
      system(RUBY, '-e', 'exit', "rlimit_cpu\0".to_sym => 3600)
    }
  end

  MANDATORY_ENVS = %w[RUBYLIB MJIT_SEARCH_BUILD_DIR]
  case RbConfig::CONFIG['target_os']
  when /linux/
    MANDATORY_ENVS << 'LD_PRELOAD'
  when /mswin|mingw/
    MANDATORY_ENVS.concat(%w[HOME USER TMPDIR])
  when /darwin/
    MANDATORY_ENVS.concat(ENV.keys.grep(/\A__CF_/))
  end
  if e = RbConfig::CONFIG['LIBPATHENV']
    MANDATORY_ENVS << e
  end
  if e = RbConfig::CONFIG['PRELOADENV'] and !e.empty?
    MANDATORY_ENVS << e
  end
  PREENVARG = ['-e', "%w[#{MANDATORY_ENVS.join(' ')}].each{|e|ENV.delete(e)}"]
  ENVARG = ['-e', 'ENV.each {|k,v| puts "#{k}=#{v}" }']
  ENVCOMMAND = [RUBY].concat(PREENVARG).concat(ENVARG)

  def test_execopts_env
    assert_raise(ArgumentError) {
      system({"F=O"=>"BAR"}, *TRUECOMMAND)
    }

    with_tmpchdir {|d|
      prog = "#{d}/notexist"
      e = assert_raise(Errno::ENOENT) {
        Process.wait Process.spawn({"FOO"=>"BAR"}, prog)
      }
      assert_equal(prog, e.message.sub(/.* - /, ''))
      e = assert_raise(Errno::ENOENT) {
        Process.wait Process.spawn({"FOO"=>"BAR"}, [prog, "blar"])
      }
      assert_equal(prog, e.message.sub(/.* - /, ''))
    }
    h = {}
    cmd = [h, RUBY]
    (ENV.keys + MANDATORY_ENVS).each do |k|
      case k
      when /\APATH\z/i
      when *MANDATORY_ENVS
        cmd << '-e' << "ENV.delete('#{k}')"
      else
        h[k] = nil
      end
    end
    cmd << '-e' << 'puts ENV.keys.map{|e|e.upcase}'
    IO.popen(cmd) {|io|
      assert_equal("PATH\n", io.read)
    }

    IO.popen([{"FOO"=>"BAR"}, *ENVCOMMAND]) {|io|
      assert_match(/^FOO=BAR$/, io.read)
    }

    with_tmpchdir {|d|
      system({"fofo"=>"haha"}, *ENVCOMMAND, STDOUT=>"out")
      assert_match(/^fofo=haha$/, File.read("out").chomp)
    }

    old = ENV["hmm"]
    begin
      ENV["hmm"] = "fufu"
      IO.popen(ENVCOMMAND) {|io| assert_match(/^hmm=fufu$/, io.read) }
      IO.popen([{"hmm"=>""}, *ENVCOMMAND]) {|io| assert_match(/^hmm=$/, io.read) }
      IO.popen([{"hmm"=>nil}, *ENVCOMMAND]) {|io| assert_not_match(/^hmm=/, io.read) }
      ENV["hmm"] = ""
      IO.popen(ENVCOMMAND) {|io| assert_match(/^hmm=$/, io.read) }
      IO.popen([{"hmm"=>""}, *ENVCOMMAND]) {|io| assert_match(/^hmm=$/, io.read) }
      IO.popen([{"hmm"=>nil}, *ENVCOMMAND]) {|io| assert_not_match(/^hmm=/, io.read) }
      ENV["hmm"] = nil
      IO.popen(ENVCOMMAND) {|io| assert_not_match(/^hmm=/, io.read) }
      IO.popen([{"hmm"=>""}, *ENVCOMMAND]) {|io| assert_match(/^hmm=$/, io.read) }
      IO.popen([{"hmm"=>nil}, *ENVCOMMAND]) {|io| assert_not_match(/^hmm=/, io.read) }
    ensure
      ENV["hmm"] = old
    end

    assert_raise_with_message(ArgumentError, /fo=fo/) {
      system({"fo=fo"=>"ha"}, *ENVCOMMAND)
    }
    assert_raise_with_message(ArgumentError, /\u{30c0}=\u{30e1}/) {
      system({"\u{30c0}=\u{30e1}"=>"ha"}, *ENVCOMMAND)
    }
  end

  def test_execopt_env_path
    bug8004 = '[ruby-core:53103] [Bug #8004]'
    Dir.mktmpdir do |d|
      open("#{d}/tmp_script.cmd", "w") {|f| f.puts ": ;"; f.chmod(0755)}
      assert_not_nil(pid = Process.spawn({"PATH" => d}, "tmp_script.cmd"), bug8004)
      wpid, st = Process.waitpid2(pid)
      assert_equal([pid, true], [wpid, st.success?], bug8004)
    end
  end

  def _test_execopts_env_popen(cmd)
    message = cmd.inspect
    IO.popen({"FOO"=>"BAR"}, cmd) {|io|
      assert_equal('FOO=BAR', io.read[/^FOO=.*/], message)
    }

    old = ENV["hmm"]
    begin
      ENV["hmm"] = "fufu"
      IO.popen(cmd) {|io| assert_match(/^hmm=fufu$/, io.read, message)}
      IO.popen({"hmm"=>""}, cmd) {|io| assert_match(/^hmm=$/, io.read, message)}
      IO.popen({"hmm"=>nil}, cmd) {|io| assert_not_match(/^hmm=/, io.read, message)}
      ENV["hmm"] = ""
      IO.popen(cmd) {|io| assert_match(/^hmm=$/, io.read, message)}
      IO.popen({"hmm"=>""}, cmd) {|io| assert_match(/^hmm=$/, io.read, message)}
      IO.popen({"hmm"=>nil}, cmd) {|io| assert_not_match(/^hmm=/, io.read, message)}
      ENV["hmm"] = nil
      IO.popen(cmd) {|io| assert_not_match(/^hmm=/, io.read, message)}
      IO.popen({"hmm"=>""}, cmd) {|io| assert_match(/^hmm=$/, io.read, message)}
      IO.popen({"hmm"=>nil}, cmd) {|io| assert_not_match(/^hmm=/, io.read, message)}
    ensure
      ENV["hmm"] = old
    end
  end

  def test_execopts_env_popen_vector
    _test_execopts_env_popen(ENVCOMMAND)
  end

  def test_execopts_env_popen_string
    with_tmpchdir do |d|
      open('test-script', 'w') do |f|
        ENVCOMMAND.each_with_index do |cmd, i|
          next if i.zero? or cmd == "-e"
          f.puts cmd
        end
      end
      _test_execopts_env_popen("#{RUBY} test-script")
    end
  end

  def test_execopts_preserve_env_on_exec_failure
    with_tmpchdir {|d|
      write_file 's', <<-"End"
        ENV["mgg"] = nil
        prog = "./nonexistent"
        begin
          Process.exec({"mgg" => "mggoo"}, [prog, prog])
        rescue Errno::ENOENT
        end
        open('out', 'w') {|f|
          f.print ENV["mgg"].inspect
        }
      End
      system(RUBY, 's')
      assert_equal(nil.inspect, File.read('out'),
        "[ruby-core:44093] [ruby-trunk - Bug #6249]")
    }
  end

  def test_execopts_env_single_word
    with_tmpchdir {|d|
      open("test_execopts_env_single_word.rb", "w") {|f|
        f.puts "print ENV['hgga']"
      }
      system({"hgga"=>"ugu"}, RUBY,
             :in => 'test_execopts_env_single_word.rb',
             :out => 'test_execopts_env_single_word.out')
      assert_equal('ugu', File.read('test_execopts_env_single_word.out'))
    }
  end

  def test_execopts_unsetenv_others
    h = {}
    MANDATORY_ENVS.each {|k| e = ENV[k] and h[k] = e}
    IO.popen([h, *ENVCOMMAND, :unsetenv_others=>true]) {|io|
      assert_equal("", io.read)
    }
    IO.popen([h.merge("A"=>"B"), *ENVCOMMAND, :unsetenv_others=>true]) {|io|
      assert_equal("A=B\n", io.read)
    }
  end

  PWD = [RUBY, '-e', 'puts Dir.pwd']

  def test_execopts_chdir
    with_tmpchdir {|d|
      IO.popen([*PWD, :chdir => d]) {|io|
        assert_equal(d, io.read.chomp)
      }
      assert_raise_with_message(Errno::ENOENT, %r"d/notexist") {
        Process.wait Process.spawn(*PWD, :chdir => "d/notexist")
      }
      n = "d/\u{1F37A}"
      assert_raise_with_message(Errno::ENOENT, /#{n}/) {
        Process.wait Process.spawn(*PWD, :chdir => n)
      }
    }
  end

  def test_execopts_open_chdir
    with_tmpchdir {|d|
      Dir.mkdir "foo"
      system(*PWD, :chdir => "foo", :out => "open_chdir_test")
      assert_file.exist?("open_chdir_test")
      assert_file.not_exist?("foo/open_chdir_test")
      assert_equal("#{d}/foo", File.read("open_chdir_test").chomp)
    }
  end

  def test_execopts_open_chdir_m17n_path
    with_tmpchdir {|d|
      Dir.mkdir "テスト"
      (pwd = PWD.dup).insert(1, '-EUTF-8:UTF-8')
      system(*pwd, :chdir => "テスト", :out => "open_chdir_テスト")
      assert_file.exist?("open_chdir_テスト")
      assert_file.not_exist?("テスト/open_chdir_テスト")
      assert_equal("#{d}/テスト", File.read("open_chdir_テスト", encoding: "UTF-8").chomp)
    }
  end if windows? || Encoding.find('locale') == Encoding::UTF_8

  def test_execopts_open_failure
    with_tmpchdir {|d|
      assert_raise_with_message(Errno::ENOENT, %r"d/notexist") {
        Process.wait Process.spawn(*PWD, :in => "d/notexist")
      }
      assert_raise_with_message(Errno::ENOENT, %r"d/notexist") {
        Process.wait Process.spawn(*PWD, :out => "d/notexist")
      }
      n = "d/\u{1F37A}"
      assert_raise_with_message(Errno::ENOENT, /#{n}/) {
        Process.wait Process.spawn(*PWD, :in => n)
      }
      assert_raise_with_message(Errno::ENOENT, /#{n}/) {
        Process.wait Process.spawn(*PWD, :out => n)
      }
    }
  end

  UMASK = [RUBY, '-e', 'printf "%04o\n", File.umask']

  def test_execopts_umask
    skip "umask is not supported" if windows?
    IO.popen([*UMASK, :umask => 0]) {|io|
      assert_equal("0000", io.read.chomp)
    }
    IO.popen([*UMASK, :umask => 0777]) {|io|
      assert_equal("0777", io.read.chomp)
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

  ECHO = lambda {|arg| [RUBY, '-e', "puts #{arg.dump}; STDOUT.flush"] }
  SORT = [RUBY, '-e', "puts ARGF.readlines.sort"]
  CAT = [RUBY, '-e', "IO.copy_stream STDIN, STDOUT"]

  def test_execopts_redirect_fd
    with_tmpchdir {|d|
      Process.wait Process.spawn(*ECHO["a"], STDOUT=>["out", File::WRONLY|File::CREAT|File::TRUNC, 0644])
      assert_equal("a", File.read("out").chomp)
      if windows?
        # currently telling to child the file modes is not supported.
        open("out", "a") {|f| f.write "0\n"}
      else
        Process.wait Process.spawn(*ECHO["0"], STDOUT=>["out", File::WRONLY|File::CREAT|File::APPEND, 0644])
        assert_equal("a\n0\n", File.read("out"))
      end
      Process.wait Process.spawn(*SORT, STDIN=>["out", File::RDONLY, 0644],
                                         STDOUT=>["out2", File::WRONLY|File::CREAT|File::TRUNC, 0644])
      assert_equal("0\na\n", File.read("out2"))
      Process.wait Process.spawn(*ECHO["b"], [STDOUT, STDERR]=>["out", File::WRONLY|File::CREAT|File::TRUNC, 0644])
      assert_equal("b", File.read("out").chomp)
      # problem occur with valgrind
      #Process.wait Process.spawn(*ECHO["a"], STDOUT=>:close, STDERR=>["out", File::WRONLY|File::CREAT|File::TRUNC, 0644])
      #p File.read("out")
      #assert_not_empty(File.read("out")) # error message such as "-e:1:in `flush': Bad file descriptor (Errno::EBADF)"
      Process.wait Process.spawn(*ECHO["c"], STDERR=>STDOUT, STDOUT=>["out", File::WRONLY|File::CREAT|File::TRUNC, 0644])
      assert_equal("c", File.read("out").chomp)
      File.open("out", "w") {|f|
        Process.wait Process.spawn(*ECHO["d"], STDOUT=>f)
        assert_equal("d", File.read("out").chomp)
      }
      opts = {STDOUT=>["out", File::WRONLY|File::CREAT|File::TRUNC, 0644]}
      opts.merge(3=>STDOUT, 4=>STDOUT, 5=>STDOUT, 6=>STDOUT, 7=>STDOUT) unless windows?
      Process.wait Process.spawn(*ECHO["e"], opts)
      assert_equal("e", File.read("out").chomp)
      opts = {STDOUT=>["out", File::WRONLY|File::CREAT|File::TRUNC, 0644]}
      opts.merge(3=>0, 4=>:in, 5=>STDIN, 6=>1, 7=>:out, 8=>STDOUT, 9=>2, 10=>:err, 11=>STDERR) unless windows?
      Process.wait Process.spawn(*ECHO["ee"], opts)
      assert_equal("ee", File.read("out").chomp)
      unless windows?
        # passing non-stdio fds is not supported on Windows
        File.open("out", "w") {|f|
          h = {STDOUT=>f, f=>STDOUT}
          3.upto(30) {|i| h[i] = STDOUT if f.fileno != i }
          Process.wait Process.spawn(*ECHO["f"], h)
          assert_equal("f", File.read("out").chomp)
        }
      end
      assert_raise(ArgumentError) {
        Process.wait Process.spawn(*ECHO["f"], 1=>Process)
      }
      assert_raise(ArgumentError) {
        Process.wait Process.spawn(*ECHO["f"], [Process]=>1)
      }
      assert_raise(ArgumentError) {
        Process.wait Process.spawn(*ECHO["f"], [1, STDOUT]=>2)
      }
      assert_raise(ArgumentError) {
        Process.wait Process.spawn(*ECHO["f"], -1=>2)
      }
      Process.wait Process.spawn(*ECHO["hhh\nggg\n"], STDOUT=>"out")
      assert_equal("hhh\nggg\n", File.read("out"))
      Process.wait Process.spawn(*SORT, STDIN=>"out", STDOUT=>"out2")
      assert_equal("ggg\nhhh\n", File.read("out2"))

      unless windows?
        # passing non-stdio fds is not supported on Windows
        assert_raise(Errno::ENOENT) {
          Process.wait Process.spawn("non-existing-command", (3..60).to_a=>["err", File::WRONLY|File::CREAT])
        }
        assert_equal("", File.read("err"))
      end

      system(*ECHO["bb\naa\n"], STDOUT=>["out", "w"])
      assert_equal("bb\naa\n", File.read("out"))
      system(*SORT, STDIN=>["out"], STDOUT=>"out2")
      assert_equal("aa\nbb\n", File.read("out2"))
    }
  end

  def test_execopts_redirect_open_order_normal
    minfd = 3
    maxfd = 20
    with_tmpchdir {|d|
      opts = {}
      minfd.upto(maxfd) {|fd| opts[fd] = ["out#{fd}", "w"] }
      system RUBY, "-e", "#{minfd}.upto(#{maxfd}) {|fd| IO.new(fd).print fd.to_s }", opts
      minfd.upto(maxfd) {|fd| assert_equal(fd.to_s, File.read("out#{fd}")) }
    }
  end unless windows? # passing non-stdio fds is not supported on Windows

  def test_execopts_redirect_open_order_reverse
    minfd = 3
    maxfd = 20
    with_tmpchdir {|d|
      opts = {}
      maxfd.downto(minfd) {|fd| opts[fd] = ["out#{fd}", "w"] }
      system RUBY, "-e", "#{minfd}.upto(#{maxfd}) {|fd| IO.new(fd).print fd.to_s }", opts
      minfd.upto(maxfd) {|fd| assert_equal(fd.to_s, File.read("out#{fd}")) }
    }
  end unless windows? # passing non-stdio fds is not supported on Windows

  def test_execopts_redirect_open_fifo
    with_tmpchdir {|d|
      begin
        File.mkfifo("fifo")
      rescue NotImplementedError
        return
      end
      assert_file.pipe?("fifo")
      t1 = Thread.new {
        system(*ECHO["output to fifo"], :out=>"fifo")
      }
      t2 = Thread.new {
        IO.popen([*CAT, :in=>"fifo"]) {|f| f.read }
      }
      _, v2 = assert_join_threads([t1, t2])
      assert_equal("output to fifo\n", v2)
    }
  end unless windows? # does not support fifo

  def test_execopts_redirect_open_fifo_interrupt_raise
    with_tmpchdir {|d|
      begin
        File.mkfifo("fifo")
      rescue NotImplementedError
        return
      end
      IO.popen([RUBY, '-e', <<-'EOS']) {|io|
        class E < StandardError; end
        trap(:USR1) { raise E }
        begin
          puts "start"
          STDOUT.flush
          system("cat", :in => "fifo")
        rescue E
          puts "ok"
        end
      EOS
        assert_equal("start\n", io.gets)
        sleep 0.5
        Process.kill(:USR1, io.pid)
        assert_equal("ok\n", io.read)
      }
    }
  end unless windows? # does not support fifo

  def test_execopts_redirect_open_fifo_interrupt_print
    with_tmpchdir {|d|
      begin
        File.mkfifo("fifo")
      rescue NotImplementedError
        return
      end
      IO.popen([RUBY, '-e', <<-'EOS']) {|io|
        STDOUT.sync = true
        trap(:USR1) { print "trap\n" }
        puts "start"
        system("cat", :in => "fifo")
      EOS
        assert_equal("start\n", io.gets)
        sleep 0.2 # wait for the child to stop at opening "fifo"
        Process.kill(:USR1, io.pid)
        assert_equal("trap\n", io.readpartial(8))
        File.write("fifo", "ok\n")
        assert_equal("ok\n", io.read)
      }
    }
  end unless windows? # does not support fifo

  def test_execopts_redirect_pipe
    with_pipe {|r1, w1|
      with_pipe {|r2, w2|
        opts = {STDIN=>r1, STDOUT=>w2}
        opts.merge(w1=>:close, r2=>:close) unless windows?
        pid = spawn(*SORT, opts)
        r1.close
        w2.close
        w1.puts "c"
        w1.puts "a"
        w1.puts "b"
        w1.close
        assert_equal("a\nb\nc\n", r2.read)
        r2.close
        Process.wait(pid)
      }
    }

    unless windows?
      # passing non-stdio fds is not supported on Windows
      with_pipes(5) {|pipes|
        ios = pipes.flatten
        h = {}
        ios.length.times {|i| h[ios[i]] = ios[(i-1)%ios.length] }
        h2 = h.invert
        _rios = pipes.map {|r, w| r }
        wios  = pipes.map {|r, w| w }
        child_wfds = wios.map {|w| h2[w].fileno }
        pid = spawn(RUBY, "-e",
                    "[#{child_wfds.join(',')}].each {|fd| IO.new(fd, 'w').puts fd }", h)
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
        _rios = pipes.map {|r, w| r }
        wios  = pipes.map {|r, w| w }
        child_wfds = wios.map {|w| h2[w].fileno }
        pid = spawn(RUBY, "-e",
                    "[#{child_wfds.join(',')}].each {|fd| IO.new(fd, 'w').puts fd }", h)
        pipes.each {|r, w|
          assert_equal("#{h2[w].fileno}\n", r.gets)
        }
        Process.wait pid
      }

      closed_fd = nil
      with_pipes(5) {|pipes|
        io = pipes.last.last
        closed_fd = io.fileno
      }
      assert_raise(Errno::EBADF) { Process.wait spawn(*TRUECOMMAND, closed_fd=>closed_fd) }

      with_pipe {|r, w|
        if w.respond_to?(:"close_on_exec=")
          w.close_on_exec = true
          pid = spawn(RUBY, "-e", "IO.new(#{w.fileno}, 'w').print 'a'", w=>w)
          w.close
          assert_equal("a", r.read)
          Process.wait pid
        end
      }

      # ensure standard FDs we redirect to are blocking for compatibility
      with_pipes(3) do |pipes|
        src = 'p [STDIN,STDOUT,STDERR].map(&:nonblock?)'
        rdr = { 0 => pipes[0][0], 1 => pipes[1][1], 2 => pipes[2][1] }
        pid = spawn(RUBY, '-rio/nonblock', '-e', src, rdr)
        assert_equal("[false, false, false]\n", pipes[1][0].gets)
        Process.wait pid
      end
    end
  end

  def test_execopts_redirect_symbol
    with_tmpchdir {|d|
      system(*ECHO["funya"], :out=>"out")
      assert_equal("funya\n", File.read("out"))
      system(RUBY, '-e', 'STDOUT.reopen(STDERR); puts "henya"', :err=>"out")
      assert_equal("henya\n", File.read("out"))
      IO.popen([*CAT, :in=>"out"]) {|io|
        assert_equal("henya\n", io.read)
      }
    }
  end

  def test_execopts_redirect_nonascii_path
    bug9946 = '[ruby-core:63185] [Bug #9946]'
    with_tmpchdir {|d|
      path = "t-\u{30c6 30b9 30c8 f6}.txt"
      system(*ECHO["a"], out: path)
      assert_file.for(bug9946).exist?(path)
      assert_equal("a\n", File.read(path), bug9946)
    }
  end

  def test_execopts_redirect_to_out_and_err
    with_tmpchdir {|d|
      ret = system(RUBY, "-e", 'STDERR.print "e"; STDOUT.print "o"', [:out, :err] => "foo")
      assert_equal(true, ret)
      assert_equal("eo", File.read("foo"))
      ret = system(RUBY, "-e", 'STDERR.print "E"; STDOUT.print "O"', [:err, :out] => "bar")
      assert_equal(true, ret)
      assert_equal("EO", File.read("bar"))
    }
  end

  def test_execopts_redirect_dup2_child
    with_tmpchdir {|d|
      Process.wait spawn(RUBY, "-e", "STDERR.print 'err'; STDOUT.print 'out'",
                         STDOUT=>"out", STDERR=>[:child, STDOUT])
      assert_equal("errout", File.read("out"))

      Process.wait spawn(RUBY, "-e", "STDERR.print 'err'; STDOUT.print 'out'",
                         STDERR=>"out", STDOUT=>[:child, STDERR])
      assert_equal("errout", File.read("out"))

      skip "inheritance of fd other than stdin,stdout and stderr is not supported" if windows?
      Process.wait spawn(RUBY, "-e", "STDERR.print 'err'; STDOUT.print 'out'",
                         STDOUT=>"out",
                         STDERR=>[:child, 3],
                         3=>[:child, 4],
                         4=>[:child, STDOUT]
                        )
      assert_equal("errout", File.read("out"))

      IO.popen([RUBY, "-e", "STDERR.print 'err'; STDOUT.print 'out'", STDERR=>[:child, STDOUT]]) {|io|
        assert_equal("errout", io.read)
      }

      assert_raise(ArgumentError) { Process.wait spawn(*TRUECOMMAND, STDOUT=>[:child, STDOUT]) }
      assert_raise(ArgumentError) { Process.wait spawn(*TRUECOMMAND, 3=>[:child, 4], 4=>[:child, 3]) }
      assert_raise(ArgumentError) { Process.wait spawn(*TRUECOMMAND, 3=>[:child, 4], 4=>[:child, 5], 5=>[:child, 3]) }
      assert_raise(ArgumentError) { Process.wait spawn(*TRUECOMMAND, STDOUT=>[:child, 3]) }
    }
  end

  def test_execopts_exec
    with_tmpchdir {|d|
      write_file("s", 'exec "echo aaa", STDOUT=>"foo"')
      pid = spawn RUBY, 's'
      Process.wait pid
      assert_equal("aaa\n", File.read("foo"))
    }
  end

  def test_execopts_popen
    with_tmpchdir {|d|
      IO.popen("#{RUBY} -e 'puts :foo'") {|io| assert_equal("foo\n", io.read) }
      assert_raise(Errno::ENOENT) { IO.popen(["echo bar"]) {} } # assuming "echo bar" command not exist.
      IO.popen(ECHO["baz"]) {|io| assert_equal("baz\n", io.read) }
    }
  end

  def test_execopts_popen_stdio
    with_tmpchdir {|d|
      assert_raise(ArgumentError) {
        IO.popen([*ECHO["qux"], STDOUT=>STDOUT]) {|io| }
      }
      IO.popen([*ECHO["hoge"], STDERR=>STDOUT]) {|io|
        assert_equal("hoge\n", io.read)
      }
      assert_raise(ArgumentError) {
        IO.popen([*ECHO["fuga"], STDOUT=>"out"]) {|io| }
      }
    }
  end

  def test_execopts_popen_extra_fd
    skip "inheritance of fd other than stdin,stdout and stderr is not supported" if windows?
    with_tmpchdir {|d|
      with_pipe {|r, w|
        IO.popen([RUBY, '-e', 'IO.new(3, "w").puts("a"); puts "b"', 3=>w]) {|io|
          assert_equal("b\n", io.read)
        }
        w.close
        assert_equal("a\n", r.read)
      }
      IO.popen([RUBY, '-e', "IO.new(9, 'w').puts(:b)",
               9=>["out2", File::WRONLY|File::CREAT|File::TRUNC]]) {|io|
        assert_equal("", io.read)
      }
      assert_equal("b\n", File.read("out2"))
    }
  end

  def test_popen_fork
    IO.popen("-") {|io|
      if !io
        puts "fooo"
      else
        assert_equal("fooo\n", io.read)
      end
    }
  rescue NotImplementedError
  end

  def test_fd_inheritance
    skip "inheritance of fd other than stdin,stdout and stderr is not supported" if windows?
    with_pipe {|r, w|
      system(RUBY, '-e', 'IO.new(ARGV[0].to_i, "w").puts(:ba)', w.fileno.to_s, w=>w)
      w.close
      assert_equal("ba\n", r.read)
    }
    with_pipe {|r, w|
      Process.wait spawn(RUBY, '-e',
                         'IO.new(ARGV[0].to_i, "w").puts("bi") rescue nil',
                         w.fileno.to_s)
      w.close
      assert_equal("", r.read)
    }
    with_pipe {|r, w|
      with_tmpchdir {|d|
	write_file("s", <<-"End")
	  exec(#{RUBY.dump}, '-e',
	       'IO.new(ARGV[0].to_i, "w").puts("bu") rescue nil',
	       #{w.fileno.to_s.dump}, :close_others=>false)
	End
        w.close_on_exec = false
	Process.wait spawn(RUBY, "s", :close_others=>false)
	w.close
	assert_equal("bu\n", r.read)
      }
    }
    with_pipe {|r, w|
      io = IO.popen([RUBY, "-e", "STDERR.reopen(STDOUT); IO.new(#{w.fileno}, 'w').puts('me')"])
      begin
        w.close
        errmsg = io.read
        assert_equal("", r.read)
        assert_not_equal("", errmsg)
      ensure
        io.close
      end
    }
    with_pipe {|r, w|
      errmsg = `#{RUBY} -e "STDERR.reopen(STDOUT); IO.new(#{w.fileno}, 'w').puts(123)"`
      w.close
      assert_equal("", r.read)
      assert_not_equal("", errmsg)
    }
  end

  def test_execopts_close_others
    skip "inheritance of fd other than stdin,stdout and stderr is not supported" if windows?
    with_tmpchdir {|d|
      with_pipe {|r, w|
        system(RUBY, '-e', 'STDERR.reopen("err", "w"); IO.new(ARGV[0].to_i, "w").puts("ma")', w.fileno.to_s, :close_others=>true)
        w.close
        assert_equal("", r.read)
        assert_not_equal("", File.read("err"))
        File.unlink("err")
      }
      with_pipe {|r, w|
        Process.wait spawn(RUBY, '-e', 'STDERR.reopen("err", "w"); IO.new(ARGV[0].to_i, "w").puts("mi")', w.fileno.to_s, :close_others=>true)
        w.close
        assert_equal("", r.read)
        assert_not_equal("", File.read("err"))
        File.unlink("err")
      }
      with_pipe {|r, w|
        w.close_on_exec = false
        Process.wait spawn(RUBY, '-e', 'IO.new(ARGV[0].to_i, "w").puts("bi")', w.fileno.to_s, :close_others=>false)
        w.close
        assert_equal("bi\n", r.read)
      }
      with_pipe {|r, w|
	write_file("s", <<-"End")
	  exec(#{RUBY.dump}, '-e',
	       'STDERR.reopen("err", "w"); IO.new(ARGV[0].to_i, "w").puts("mu")',
	       #{w.fileno.to_s.dump},
	       :close_others=>true)
	End
        Process.wait spawn(RUBY, "s", :close_others=>false)
        w.close
        assert_equal("", r.read)
        assert_not_equal("", File.read("err"))
        File.unlink("err")
      }
      with_pipe {|r, w|
        io = IO.popen([RUBY, "-e", "STDERR.reopen(STDOUT); IO.new(#{w.fileno}, 'w').puts('me')", :close_others=>true])
        begin
          w.close
          errmsg = io.read
          assert_equal("", r.read)
          assert_not_equal("", errmsg)
        ensure
          io.close
        end
      }
      with_pipe {|r, w|
        w.close_on_exec = false
        io = IO.popen([RUBY, "-e", "STDERR.reopen(STDOUT); IO.new(#{w.fileno}, 'w').puts('mo')", :close_others=>false])
        begin
          w.close
          errmsg = io.read
          assert_equal("mo\n", r.read)
          assert_equal("", errmsg)
        ensure
          io.close
        end
      }
      with_pipe {|r, w|
        w.close_on_exec = false
        io = IO.popen([RUBY, "-e", "STDERR.reopen(STDOUT); IO.new(#{w.fileno}, 'w').puts('mo')", :close_others=>nil])
        begin
          w.close
          errmsg = io.read
          assert_equal("mo\n", r.read)
          assert_equal("", errmsg)
        ensure
          io.close
        end
      }

    }
  end

  def test_close_others_default_false
    IO.pipe do |r,w|
      w.close_on_exec = false
      src = "IO.new(#{w.fileno}).puts(:hi)"
      assert_equal true, system(*%W(#{RUBY} --disable=gems -e #{src}))
      assert_equal "hi\n", r.gets
    end
  end unless windows? # passing non-stdio fds is not supported on Windows

  def test_execopts_redirect_self
    begin
      with_pipe {|r, w|
        w << "haha\n"
        w.close
        r.close_on_exec = true
        IO.popen([RUBY, "-e", "print IO.new(#{r.fileno}, 'r').read", r.fileno=>r.fileno, :close_others=>false]) {|io|
          assert_equal("haha\n", io.read)
        }
      }
    rescue NotImplementedError
      skip "IO#close_on_exec= is not supported"
    end
  end unless windows? # passing non-stdio fds is not supported on Windows

  def test_execopts_redirect_tempfile
    bug6269 = '[ruby-core:44181]'
    Tempfile.create("execopts") do |tmp|
      pid = assert_nothing_raised(ArgumentError, bug6269) do
        break spawn(RUBY, "-e", "print $$", out: tmp)
      end
      Process.wait(pid)
      tmp.rewind
      assert_equal(pid.to_s, tmp.read)
    end
  end

  def test_execopts_duplex_io
    IO.popen("#{RUBY} -e ''", "r+") {|duplex|
      assert_raise(ArgumentError) { system("#{RUBY} -e ''", duplex=>STDOUT) }
      assert_raise(ArgumentError) { system("#{RUBY} -e ''", STDOUT=>duplex) }
    }
  end

  def test_execopts_modification
    h = {}
    Process.wait spawn(*TRUECOMMAND, h)
    assert_equal({}, h)

    h = {}
    system(*TRUECOMMAND, h)
    assert_equal({}, h)

    h = {}
    io = IO.popen([*TRUECOMMAND, h])
    io.close
    assert_equal({}, h)
  end

  def test_system_noshell
    str = "echo non existing command name which contains spaces"
    assert_nil(system([str, str]))
  end

  def test_spawn_noshell
    str = "echo non existing command name which contains spaces"
    assert_raise(Errno::ENOENT) { spawn([str, str]) }
  end

  def test_popen_noshell
    str = "echo non existing command name which contains spaces"
    assert_raise(Errno::ENOENT) { IO.popen([str, str]) }
  end

  def test_exec_noshell
    with_tmpchdir {|d|
      write_file("s", <<-"End")
	  str = "echo non existing command name which contains spaces"
	  STDERR.reopen(STDOUT)
	  begin
	    exec [str, str]
	  rescue Errno::ENOENT
	    print "Errno::ENOENT success"
	  end
	End
      r = IO.popen([RUBY, "s", :close_others=>false], "r") {|f| f.read}
      assert_equal("Errno::ENOENT success", r)
    }
  end

  def test_system_wordsplit
    with_tmpchdir {|d|
      write_file("script", <<-'End')
        File.open("result", "w") {|t| t << "haha pid=#{$$} ppid=#{Process.ppid}" }
        exit 5
      End
      str = "#{RUBY} script"
      ret = system(str)
      status = $?
      assert_equal(false, ret)
      assert_predicate(status, :exited?)
      assert_equal(5, status.exitstatus)
      assert_equal("haha pid=#{status.pid} ppid=#{$$}", File.read("result"))
    }
  end

  def test_spawn_wordsplit
    with_tmpchdir {|d|
      write_file("script", <<-'End')
        File.open("result", "w") {|t| t << "hihi pid=#{$$} ppid=#{Process.ppid}" }
        exit 6
      End
      str = "#{RUBY} script"
      pid = spawn(str)
      Process.wait pid
      status = $?
      assert_equal(pid, status.pid)
      assert_predicate(status, :exited?)
      assert_equal(6, status.exitstatus)
      assert_equal("hihi pid=#{status.pid} ppid=#{$$}", File.read("result"))
    }
  end

  def test_popen_wordsplit
    with_tmpchdir {|d|
      write_file("script", <<-'End')
        print "fufu pid=#{$$} ppid=#{Process.ppid}"
        exit 7
      End
      str = "#{RUBY} script"
      io = IO.popen(str)
      pid = io.pid
      result = io.read
      io.close
      status = $?
      assert_equal(pid, status.pid)
      assert_predicate(status, :exited?)
      assert_equal(7, status.exitstatus)
      assert_equal("fufu pid=#{status.pid} ppid=#{$$}", result)
    }
  end

  def test_popen_wordsplit_beginning_and_trailing_spaces
    with_tmpchdir {|d|
      write_file("script", <<-'End')
        print "fufumm pid=#{$$} ppid=#{Process.ppid}"
        exit 7
      End
      str = " #{RUBY} script "
      io = IO.popen(str)
      pid = io.pid
      result = io.read
      io.close
      status = $?
      assert_equal(pid, status.pid)
      assert_predicate(status, :exited?)
      assert_equal(7, status.exitstatus)
      assert_equal("fufumm pid=#{status.pid} ppid=#{$$}", result)
    }
  end

  def test_exec_wordsplit
    with_tmpchdir {|d|
      write_file("script", <<-'End')
        File.open("result", "w") {|t|
          if /mswin|bccwin|mingw/ =~ RUBY_PLATFORM
            t << "hehe ppid=#{Process.ppid}"
          else
            t << "hehe pid=#{$$} ppid=#{Process.ppid}"
          end
        }
        exit 6
      End
      write_file("s", <<-"End")
	ruby = #{RUBY.dump}
	exec "\#{ruby} script"
      End
      pid = spawn(RUBY, "s")
      Process.wait pid
      status = $?
      assert_equal(pid, status.pid)
      assert_predicate(status, :exited?)
      assert_equal(6, status.exitstatus)
      if windows?
        expected = "hehe ppid=#{status.pid}"
      else
        expected = "hehe pid=#{status.pid} ppid=#{$$}"
      end
      assert_equal(expected, File.read("result"))
    }
  end

  def test_system_shell
    with_tmpchdir {|d|
      write_file("script1", <<-'End')
        File.open("result1", "w") {|t| t << "taka pid=#{$$} ppid=#{Process.ppid}" }
        exit 7
      End
      write_file("script2", <<-'End')
        File.open("result2", "w") {|t| t << "taki pid=#{$$} ppid=#{Process.ppid}" }
        exit 8
      End
      ret = system("#{RUBY} script1 || #{RUBY} script2")
      status = $?
      assert_equal(false, ret)
      assert_predicate(status, :exited?)
      result1 = File.read("result1")
      result2 = File.read("result2")
      assert_match(/\Ataka pid=\d+ ppid=\d+\z/, result1)
      assert_match(/\Ataki pid=\d+ ppid=\d+\z/, result2)
      assert_not_equal(result1[/\d+/].to_i, status.pid)

      if windows?
        Dir.mkdir(path = "path with space")
        write_file(bat = path + "/bat test.bat", "@echo %1>out")
        system(bat, "foo 'bar'")
        assert_equal(%["foo 'bar'"\n], File.read("out"), '[ruby-core:22960]')
        system(%[#{bat.dump} "foo 'bar'"])
        assert_equal(%["foo 'bar'"\n], File.read("out"), '[ruby-core:22960]')
      end
    }
  end

  def test_spawn_shell
    with_tmpchdir {|d|
      write_file("script1", <<-'End')
        File.open("result1", "w") {|t| t << "taku pid=#{$$} ppid=#{Process.ppid}" }
        exit 7
      End
      write_file("script2", <<-'End')
        File.open("result2", "w") {|t| t << "take pid=#{$$} ppid=#{Process.ppid}" }
        exit 8
      End
      pid = spawn("#{RUBY} script1 || #{RUBY} script2")
      Process.wait pid
      status = $?
      assert_predicate(status, :exited?)
      assert_not_predicate(status, :success?)
      result1 = File.read("result1")
      result2 = File.read("result2")
      assert_match(/\Ataku pid=\d+ ppid=\d+\z/, result1)
      assert_match(/\Atake pid=\d+ ppid=\d+\z/, result2)
      assert_not_equal(result1[/\d+/].to_i, status.pid)

      if windows?
        Dir.mkdir(path = "path with space")
        write_file(bat = path + "/bat test.bat", "@echo %1>out")
        pid = spawn(bat, "foo 'bar'")
        Process.wait pid
        status = $?
        assert_predicate(status, :exited?)
        assert_predicate(status, :success?)
        assert_equal(%["foo 'bar'"\n], File.read("out"), '[ruby-core:22960]')
        pid = spawn(%[#{bat.dump} "foo 'bar'"])
        Process.wait pid
        status = $?
        assert_predicate(status, :exited?)
        assert_predicate(status, :success?)
        assert_equal(%["foo 'bar'"\n], File.read("out"), '[ruby-core:22960]')
      end
    }
  end

  def test_popen_shell
    with_tmpchdir {|d|
      write_file("script1", <<-'End')
        puts "tako pid=#{$$} ppid=#{Process.ppid}"
        exit 7
      End
      write_file("script2", <<-'End')
        puts "tika pid=#{$$} ppid=#{Process.ppid}"
        exit 8
      End
      io = IO.popen("#{RUBY} script1 || #{RUBY} script2")
      result = io.read
      io.close
      status = $?
      assert_predicate(status, :exited?)
      assert_not_predicate(status, :success?)
      assert_match(/\Atako pid=\d+ ppid=\d+\ntika pid=\d+ ppid=\d+\n\z/, result)
      assert_not_equal(result[/\d+/].to_i, status.pid)

      if windows?
        Dir.mkdir(path = "path with space")
        write_file(bat = path + "/bat test.bat", "@echo %1")
        r = IO.popen([bat, "foo 'bar'"]) {|f| f.read}
        assert_equal(%["foo 'bar'"\n], r, '[ruby-core:22960]')
        r = IO.popen(%[#{bat.dump} "foo 'bar'"]) {|f| f.read}
        assert_equal(%["foo 'bar'"\n], r, '[ruby-core:22960]')
      end
    }
  end

  def test_exec_shell
    with_tmpchdir {|d|
      write_file("script1", <<-'End')
        File.open("result1", "w") {|t| t << "tiki pid=#{$$} ppid=#{Process.ppid}" }
        exit 7
      End
      write_file("script2", <<-'End')
        File.open("result2", "w") {|t| t << "tiku pid=#{$$} ppid=#{Process.ppid}" }
        exit 8
      End
      write_file("s", <<-"End")
	ruby = #{RUBY.dump}
	exec("\#{ruby} script1 || \#{ruby} script2")
      End
      pid = spawn RUBY, "s"
      Process.wait pid
      status = $?
      assert_predicate(status, :exited?)
      assert_not_predicate(status, :success?)
      result1 = File.read("result1")
      result2 = File.read("result2")
      assert_match(/\Atiki pid=\d+ ppid=\d+\z/, result1)
      assert_match(/\Atiku pid=\d+ ppid=\d+\z/, result2)
      assert_not_equal(result1[/\d+/].to_i, status.pid)
    }
  end

  def test_argv0
    with_tmpchdir {|d|
      assert_equal(false, system([RUBY, "asdfg"], "-e", "exit false"))
      assert_equal(true, system([RUBY, "zxcvb"], "-e", "exit true"))

      Process.wait spawn([RUBY, "poiu"], "-e", "exit 4")
      assert_equal(4, $?.exitstatus)

      assert_equal("1", IO.popen([[RUBY, "qwerty"], "-e", "print 1"]) {|f| f.read })

      write_file("s", <<-"End")
        exec([#{RUBY.dump}, "lkjh"], "-e", "exit 5")
      End
      pid = spawn RUBY, "s"
      Process.wait pid
      assert_equal(5, $?.exitstatus)
    }
  end

  def with_stdin(filename)
    open(filename) {|f|
      begin
        old = STDIN.dup
        begin
          STDIN.reopen(filename)
          yield
        ensure
          STDIN.reopen(old)
        end
      ensure
        old.close
      end
    }
  end

  def test_argv0_noarg
    with_tmpchdir {|d|
      open("t", "w") {|f| f.print "exit true" }
      open("f", "w") {|f| f.print "exit false" }

      with_stdin("t") { assert_equal(true, system([RUBY, "qaz"])) }
      with_stdin("f") { assert_equal(false, system([RUBY, "wsx"])) }

      with_stdin("t") { Process.wait spawn([RUBY, "edc"]) }
      assert_predicate($?, :success?)
      with_stdin("f") { Process.wait spawn([RUBY, "rfv"]) }
      assert_not_predicate($?, :success?)

      with_stdin("t") { IO.popen([[RUBY, "tgb"]]) {|io| assert_equal("", io.read) } }
      assert_predicate($?, :success?)
      with_stdin("f") { IO.popen([[RUBY, "yhn"]]) {|io| assert_equal("", io.read) } }
      assert_not_predicate($?, :success?)

      status = run_in_child "STDIN.reopen('t'); exec([#{RUBY.dump}, 'ujm'])"
      assert_predicate(status, :success?)
      status = run_in_child "STDIN.reopen('f'); exec([#{RUBY.dump}, 'ik,'])"
      assert_not_predicate(status, :success?)
    }
  end

  def test_argv0_keep_alive
    assert_in_out_err([], <<~REPRO, ['-'], [], "[Bug #15887]")
      $0 = "diverge"
      4.times { GC.start }
      puts Process.argv0
    REPRO
  end

  def test_status
    with_tmpchdir do
      s = run_in_child("exit 1")
      assert_equal("#<Process::Status: pid #{ s.pid } exit #{ s.exitstatus }>", s.inspect)

      assert_equal(s, s)
      assert_equal(s, s.to_i)

      assert_equal(s.to_i & 0x55555555, s & 0x55555555)
      assert_equal(s.to_i >> 1, s >> 1)
      assert_equal(false, s.stopped?)
      assert_equal(nil, s.stopsig)
    end
  end

  def test_status_kill
    return unless Process.respond_to?(:kill)
    return unless Signal.list.include?("KILL")

    # assume the system supports signal if SIGQUIT is available
    expected = Signal.list.include?("QUIT") ? [false, true, false, nil] : [true, false, false, true]

    with_tmpchdir do
      write_file("foo", "Process.kill(:KILL, $$); exit(42)")
      system(RUBY, "foo")
      s = $?
      assert_equal(expected,
                   [s.exited?, s.signaled?, s.stopped?, s.success?],
                   "[s.exited?, s.signaled?, s.stopped?, s.success?]")
    end
  end

  def test_status_quit
    return unless Process.respond_to?(:kill)
    return unless Signal.list.include?("QUIT")

    with_tmpchdir do
      s = assert_in_out_err([], "Signal.trap(:QUIT,'DEFAULT'); Process.kill(:SIGQUIT, $$);sleep 30", //, //, rlimit_core: 0)
      assert_equal([false, true, false, nil],
                   [s.exited?, s.signaled?, s.stopped?, s.success?],
                   "[s.exited?, s.signaled?, s.stopped?, s.success?]")
      assert_equal("#<Process::Status: pid #{ s.pid } SIGQUIT (signal #{ s.termsig })>",
                   s.inspect.sub(/ \(core dumped\)(?=>\z)/, ''))
    end
  end

  def test_wait_without_arg
    with_tmpchdir do
      write_file("foo", "sleep 0.1")
      pid = spawn(RUBY, "foo")
      assert_equal(pid, Process.wait)
    end
  end

  def test_wait2
    with_tmpchdir do
      write_file("foo", "sleep 0.1")
      pid = spawn(RUBY, "foo")
      assert_equal([pid, 0], Process.wait2)
    end
  end

  def test_waitall
    with_tmpchdir do
      write_file("foo", "sleep 0.1")
      ps = (0...3).map { spawn(RUBY, "foo") }.sort
      ss = Process.waitall.sort
      ps.zip(ss) do |p1, (p2, s)|
        assert_equal(p1, p2)
        assert_equal(p1, s.pid)
      end
    end
  end

  def test_wait_exception
    bug11340 = '[ruby-dev:49176] [Bug #11340]'
    t0 = t1 = nil
    sec = 3
    code = "puts;STDOUT.flush;Thread.start{gets;exit};sleep(#{sec})"
    IO.popen([RUBY, '-e', code], 'r+') do |f|
      pid = f.pid
      f.gets
      t0 = Time.now
      th = Thread.start(Thread.current) do |main|
        Thread.pass until main.stop?
        main.raise Interrupt
      end
      begin
        assert_raise(Interrupt) {Process.wait(pid)}
      ensure
        th.kill.join
      end
      t1 = Time.now
      diff = t1 - t0
      assert_operator(diff, :<, sec,
                  ->{"#{bug11340}: #{diff} seconds to interrupt Process.wait"})
      f.puts
    end
  end

  def test_abort
    with_tmpchdir do
      s = run_in_child("abort")
      assert_not_predicate(s, :success?)
      write_file("test-script", "#{<<~"begin;"}\n#{<<~'end;'}")
      begin;
        STDERR.reopen(STDOUT)
        begin
          raise "[Bug #16424]"
        rescue
          abort
        end
      end;
      assert_include(IO.popen([RUBY, "test-script"], &:read), "[Bug #16424]")
    end
  end

  def test_sleep
    assert_raise(ArgumentError) { sleep(1, 1) }
    [-1, -1.0, -1r].each do |sec|
      assert_raise_with_message(ArgumentError, /not.*negative/) { sleep(sec) }
    end
  end

  def test_getpgid
    assert_kind_of(Integer, Process.getpgid(Process.ppid))
  rescue NotImplementedError
  end

  def test_getpriority
    assert_kind_of(Integer, Process.getpriority(Process::PRIO_PROCESS, $$))
  rescue NameError, NotImplementedError
  end

  def test_setpriority
    if defined? Process::PRIO_USER
      assert_nothing_raised do
        pr = Process.getpriority(Process::PRIO_PROCESS, $$)
        Process.setpriority(Process::PRIO_PROCESS, $$, pr)
      end
    end
  end

  def test_getuid
    assert_kind_of(Integer, Process.uid)
  end

  def test_groups
    gs = Process.groups
    assert_instance_of(Array, gs)
    gs.each {|g| assert_kind_of(Integer, g) }
  rescue NotImplementedError
  end

  def test_maxgroups
    max = Process.maxgroups
  rescue NotImplementedError
  else
    assert_kind_of(Integer, max)
    assert_predicate(max, :positive?)
    skip "not limited to NGROUPS_MAX" if /darwin/ =~ RUBY_PLATFORM
    gs = Process.groups
    assert_operator(gs.size, :<=, max)
    gs[0] ||= 0
    assert_raise(ArgumentError) {Process.groups = gs * (max / gs.size + 1)}
  end

  def test_geteuid
    assert_kind_of(Integer, Process.euid)
  end

  def test_seteuid
    assert_nothing_raised(TypeError) {Process.euid += 0}
  rescue NotImplementedError
  end

  def test_seteuid_name
    user = (Etc.getpwuid(Process.euid).name rescue ENV["USER"]) or return
    assert_nothing_raised(TypeError) {Process.euid = user}
  rescue NotImplementedError
  end

  def test_getegid
    assert_kind_of(Integer, Process.egid)
  end

  def test_setegid
    skip "root can use Process.egid on Android platform" if RUBY_PLATFORM =~ /android/
    assert_nothing_raised(TypeError) {Process.egid += 0}
  rescue NotImplementedError
  end

  if Process::UID.respond_to?(:from_name)
    def test_uid_from_name
      if u = Etc.getpwuid(Process.uid)
        assert_equal(Process.uid, Process::UID.from_name(u.name), u.name)
      end
      assert_raise_with_message(ArgumentError, /\u{4e0d 5b58 5728}/) {
        Process::UID.from_name("\u{4e0d 5b58 5728}")
      }
    end
  end

  if Process::GID.respond_to?(:from_name) && !RUBY_PLATFORM.include?("android")
    def test_gid_from_name
      if g = Etc.getgrgid(Process.gid)
        assert_equal(Process.gid, Process::GID.from_name(g.name), g.name)
      end
      expected_excs = [ArgumentError]
      expected_excs << Errno::ENOENT if defined?(Errno::ENOENT)
      expected_excs << Errno::ESRCH if defined?(Errno::ESRCH) # WSL 2 actually raises Errno::ESRCH
      expected_excs << Errno::EBADF if defined?(Errno::EBADF)
      expected_excs << Errno::EPERM if defined?(Errno::EPERM)
      exc = assert_raise(*expected_excs) do
        Process::GID.from_name("\u{4e0d 5b58 5728}") # fu son zai ("absent" in Kanji)
      end
      assert_match(/\u{4e0d 5b58 5728}/, exc.message) if exc.is_a?(ArgumentError)
    end
  end

  def test_uid_re_exchangeable_p
    r = Process::UID.re_exchangeable?
    assert_include([true, false], r)
  end

  def test_gid_re_exchangeable_p
    r = Process::GID.re_exchangeable?
    assert_include([true, false], r)
  end

  def test_uid_sid_available?
    r = Process::UID.sid_available?
    assert_include([true, false], r)
  end

  def test_gid_sid_available?
    r = Process::GID.sid_available?
    assert_include([true, false], r)
  end

  def test_pst_inspect
    assert_nothing_raised { Process::Status.allocate.inspect }
  end

  def test_wait_and_sigchild
    if /freebsd|openbsd/ =~ RUBY_PLATFORM
      # this relates #4173
      # When ruby can use 2 cores, signal and wait4 may miss the signal.
      skip "this fails on FreeBSD and OpenBSD on multithreaded environment"
    end
    signal_received = []
    IO.pipe do |sig_r, sig_w|
      Signal.trap(:CHLD) do
        signal_received << true
        sig_w.write('?')
      end
      pid = nil
      IO.pipe do |r, w|
        pid = fork { r.read(1); exit }
        Thread.start {
          Thread.current.report_on_exception = false
          raise
        }
        w.puts
      end
      Process.wait pid
      assert_send [sig_r, :wait_readable, 5], 'self-pipe not readable'
    end
    if defined?(RubyVM::MJIT) && RubyVM::MJIT.enabled? # checking -DMJIT_FORCE_ENABLE. It may trigger extra SIGCHLD.
      assert_equal [true], signal_received.uniq, "[ruby-core:19744]"
    else
      assert_equal [true], signal_received, "[ruby-core:19744]"
    end
  rescue NotImplementedError, ArgumentError
  ensure
    begin
      Signal.trap(:CHLD, 'DEFAULT')
    rescue ArgumentError
    end
  end

  def test_no_curdir
    with_tmpchdir {|d|
      Dir.mkdir("vd")
      status = nil
      Dir.chdir("vd") {
        dir = "#{d}/vd"
        # OpenSolaris cannot remove the current directory.
        system(RUBY, "--disable-gems", "-e", "Dir.chdir '..'; Dir.rmdir #{dir.dump}", err: File::NULL)
        system({"RUBYLIB"=>nil}, RUBY, "--disable-gems", "-e", "exit true")
        status = $?
      }
      assert_predicate(status, :success?, "[ruby-dev:38105]")
    }
  end

  def test_fallback_to_sh
    feature = '[ruby-core:32745]'
    with_tmpchdir do |d|
      open("tmp_script.#{$$}", "w") {|f| f.puts ": ;"; f.chmod(0755)}
      assert_not_nil(pid = Process.spawn("./tmp_script.#{$$}"), feature)
      wpid, st = Process.waitpid2(pid)
      assert_equal([pid, true], [wpid, st.success?], feature)

      open("tmp_script.#{$$}", "w") {|f| f.puts "echo $#: $@"; f.chmod(0755)}
      result = IO.popen(["./tmp_script.#{$$}", "a b", "c"]) {|f| f.read}
      assert_equal("2: a b c\n", result, feature)

      open("tmp_script.#{$$}", "w") {|f| f.puts "echo $hghg"; f.chmod(0755)}
      result = IO.popen([{"hghg" => "mogomogo"}, "./tmp_script.#{$$}", "a b", "c"]) {|f| f.read}
      assert_equal("mogomogo\n", result, feature)

    end
  end if File.executable?("/bin/sh")

  def test_spawn_too_long_path
    bug4314 = '[ruby-core:34842]'
    assert_fail_too_long_path(%w"echo", bug4314)
  end

  def test_aspawn_too_long_path
    if /solaris/i =~ RUBY_PLATFORM && !defined?(Process::RLIMIT_NPROC)
      skip "Too exhaustive test on platforms without Process::RLIMIT_NPROC such as Solaris 10"
    end
    bug4315 = '[ruby-core:34833] #7904 [ruby-core:52628] #11613'
    assert_fail_too_long_path(%w"echo |", bug4315)
  end

  def assert_fail_too_long_path((cmd, sep), mesg)
    sep ||= ""
    min = 1_000 / (cmd.size + sep.size)
    cmds = Array.new(min, cmd)
    exs = [Errno::ENOENT]
    exs << Errno::E2BIG if defined?(Errno::E2BIG)
    opts = {[STDOUT, STDERR]=>File::NULL}
    opts[:rlimit_nproc] = 128 if defined?(Process::RLIMIT_NPROC)
    EnvUtil.suppress_warning do
      assert_raise(*exs, mesg) do
        begin
          loop do
            Process.spawn(cmds.join(sep), opts)
            min = [cmds.size, min].max
            cmds *= 100
          end
        rescue NoMemoryError
          size = cmds.size
          raise if min >= size - 1
          min = [min, size /= 2].max
          cmds[size..-1] = []
          raise if size < 250
          retry
        end
      end
    end
  end

  def test_system_sigpipe
    return if windows?

    pid = 0

    with_tmpchdir do
      assert_nothing_raised('[ruby-dev:12261]') do
        EnvUtil.timeout(3) do
          pid = spawn('yes | ls')
          Process.waitpid pid
        end
      end
    end
  ensure
    Process.kill(:KILL, pid) if (pid != 0) rescue false
  end

  if Process.respond_to?(:daemon)
    def test_daemon_default
      data = IO.popen("-", "r+") do |f|
        break f.read if f
        Process.daemon
        puts "ng"
      end
      assert_equal("", data)
    end

    def test_daemon_noclose
      data = IO.popen("-", "r+") do |f|
        break f.read if f
        Process.daemon(false, true)
        puts "ok", Dir.pwd
      end
      assert_equal("ok\n/\n", data)
    end

    def test_daemon_nochdir_noclose
      data = IO.popen("-", "r+") do |f|
        break f.read if f
        Process.daemon(true, true)
        puts "ok", Dir.pwd
      end
      assert_equal("ok\n#{Dir.pwd}\n", data)
    end

    def test_daemon_readwrite
      data = IO.popen("-", "r+") do |f|
        if f
          f.puts "ok?"
          break f.read
        end
        Process.daemon(true, true)
        puts STDIN.gets
      end
      assert_equal("ok?\n", data)
    end

    def test_daemon_pid
      cpid, dpid = IO.popen("-", "r+") do |f|
        break f.pid, Integer(f.read) if f
        Process.daemon(false, true)
        puts $$
      end
      assert_not_equal(cpid, dpid)
    end

    if File.directory?("/proc/self/task") && /netbsd[a-z]*[1-6]/ !~ RUBY_PLATFORM
      def test_daemon_no_threads
        pid, data = IO.popen("-", "r+") do |f|
          break f.pid, f.readlines if f
          Process.daemon(true, true)
          puts Dir.entries("/proc/self/task") - %W[. ..]
        end
        bug4920 = '[ruby-dev:43873]'
        assert_include(1..2, data.size, bug4920)
        assert_not_include(data.map(&:to_i), pid)
      end
    else # darwin
      def test_daemon_no_threads
        data = EnvUtil.timeout(3) do
          IO.popen("-") do |f|
            break f.readlines.map(&:chomp) if f
            th = Thread.start {sleep 3}
            Process.daemon(true, true)
            puts Thread.list.size, th.status.inspect
          end
        end
        assert_equal(["1", "false"], data)
      end
    end
  end

  def test_popen_cloexec
    return unless defined? Fcntl::FD_CLOEXEC
    IO.popen([RUBY, "-e", ""]) {|io|
      assert_predicate(io, :close_on_exec?)
    }
  end

  def test_popen_exit
    bug11510 = '[ruby-core:70671] [Bug #11510]'
    pid = nil
    opt = {timeout: 10, stdout_filter: ->(s) {pid = s}}
    if windows?
      opt[:new_pgroup] = true
    else
      opt[:pgroup] = true
    end
    assert_ruby_status(["-", RUBY], <<-'end;', bug11510, **opt)
      RUBY = ARGV[0]
      th = Thread.start {
        Thread.current.abort_on_exception = true
        IO.popen([RUBY, "-esleep 15", err: [:child, :out]]) {|f|
          STDOUT.puts f.pid
          STDOUT.flush
          sleep(2)
        }
      }
      sleep(0.001) until th.stop?
    end;
    assert_match(/\A\d+\Z/, pid)
  ensure
    if pid
      pid = pid.to_i
      [:TERM, :KILL].each {|sig| Process.kill(sig, pid) rescue break}
    end
  end

  def test_popen_reopen
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      io = File.open(IO::NULL)
      io2 = io.dup
      IO.popen("echo") {|f| io.reopen(f)}
      io.reopen(io2)
    end;
  end

  def test_execopts_new_pgroup
    return unless windows?

    assert_nothing_raised { system(*TRUECOMMAND, :new_pgroup=>true) }
    assert_nothing_raised { system(*TRUECOMMAND, :new_pgroup=>false) }
    assert_nothing_raised { spawn(*TRUECOMMAND, :new_pgroup=>true) }
    assert_nothing_raised { IO.popen([*TRUECOMMAND, :new_pgroup=>true]) {} }
  end

  def test_execopts_uid
    skip "root can use uid option of Kernel#system on Android platform" if RUBY_PLATFORM =~ /android/
    feature6975 = '[ruby-core:47414]'

    [30000, [Process.uid, ENV["USER"]]].each do |uid, user|
      if user
        assert_nothing_raised(feature6975) do
          begin
            system(*TRUECOMMAND, uid: user, exception: true)
          rescue Errno::EPERM, Errno::EACCES, NotImplementedError
          end
        end
      end

      assert_nothing_raised(feature6975) do
        begin
          system(*TRUECOMMAND, uid: uid, exception: true)
        rescue Errno::EPERM, Errno::EACCES, NotImplementedError
        end
      end

      assert_nothing_raised(feature6975) do
        begin
          u = IO.popen([RUBY, "-e", "print Process.uid", uid: user||uid], &:read)
          assert_equal(uid.to_s, u, feature6975)
        rescue Errno::EPERM, Errno::EACCES, NotImplementedError
        end
      end
    end
  end

  def test_execopts_gid
    skip "Process.groups not implemented on Windows platform" if windows?
    skip "root can use Process.groups on Android platform" if RUBY_PLATFORM =~ /android/
    feature6975 = '[ruby-core:47414]'

    groups = Process.groups.map do |g|
      g = Etc.getgrgid(g) rescue next
      [g.name, g.gid]
    end
    groups.compact!
    [30000, *groups].each do |group, gid|
      assert_nothing_raised(feature6975) do
        begin
          system(*TRUECOMMAND, gid: group)
        rescue Errno::EPERM, NotImplementedError
        end
      end

      gid = "#{gid || group}"
      assert_nothing_raised(feature6975) do
        begin
          g = IO.popen([RUBY, "-e", "print Process.gid", gid: group], &:read)
          # AIX allows a non-root process to setgid to its supplementary group,
          # while other UNIXes do not. (This might be AIX's violation of the POSIX standard.)
          # However, Ruby does not allow a setgid'ed Ruby process to use the -e option.
          # As a result, the Ruby process invoked by "IO.popen([RUBY, "-e", ..." above fails
          # with a message like "no -e allowed while running setgid (SecurityError)" to stderr,
          # the exis status is set to 1, and the variable "g" is set to an empty string.
          # To conclude, on AIX, if the "gid" variable is a supplementary group,
          # the assert_equal next can fail, so skip it.
          assert_equal(gid, g, feature6975) unless $?.exitstatus == 1 && /aix/ =~ RUBY_PLATFORM && gid != Process.gid
        rescue Errno::EPERM, NotImplementedError
        end
      end
    end
  end

  def test_sigpipe
    system(RUBY, "-e", "")
    with_pipe {|r, w|
      r.close
      assert_raise(Errno::EPIPE) { w.print "a" }
    }
  end

  def test_sh_comment
    IO.popen("echo a # fofoof") {|f|
      assert_equal("a\n", f.read)
    }
  end if File.executable?("/bin/sh")

  def test_sh_env
    IO.popen("foofoo=barbar env") {|f|
      lines = f.readlines
      assert_operator(lines, :include?, "foofoo=barbar\n")
    }
  end if File.executable?("/bin/sh")

  def test_sh_exec
    IO.popen("exec echo exexexec") {|f|
      assert_equal("exexexec\n", f.read)
    }
  end if File.executable?("/bin/sh")

  def test_setsid
    return unless Process.respond_to?(:setsid)
    return unless Process.respond_to?(:getsid)
    # OpenBSD and AIX don't allow Process::getsid(pid) when pid is in
    # different session.
    return if /openbsd|aix/ =~ RUBY_PLATFORM

    IO.popen([RUBY, "-e", <<EOS]) do|io|
	Marshal.dump(Process.getsid, STDOUT)
	newsid = Process.setsid
	Marshal.dump(newsid, STDOUT)
	STDOUT.flush
	# getsid() on MacOS X return ESRCH when target process is zombie
	# even if it is valid process id.
	sleep
EOS
      begin
        # test Process.getsid() w/o arg
        assert_equal(Marshal.load(io), Process.getsid)

        # test Process.setsid return value and Process::getsid(pid)
        assert_equal(Marshal.load(io), Process.getsid(io.pid))
      ensure
        Process.kill(:KILL, io.pid) rescue nil
        Process.wait(io.pid)
      end
    end
  end

  def test_spawn_nonascii
    bug1771 = '[ruby-core:24309] [Bug #1771]'

    with_tmpchdir do
      [
       "\u{7d05 7389}",
       "zuf\u{00E4}llige_\u{017E}lu\u{0165}ou\u{010D}k\u{00FD}_\u{10D2 10D0 10DB 10D4 10DD 10E0 10D4 10D1}_\u{0440 0430 0437 043B 043E 0433 0430}_\u{548C 65B0 52A0 5761 4EE5 53CA 4E1C}",
       "c\u{1EE7}a",
      ].each do |name|
        msg = "#{bug1771} #{name}"
        exename = "./#{name}.exe"
        FileUtils.cp(ENV["COMSPEC"], exename)
        assert_equal(true, system("#{exename} /c exit"), msg)
        system("#{exename} /c exit 12")
        assert_equal(12, $?.exitstatus, msg)
        _, status = Process.wait2(Process.spawn("#{exename} /c exit 42"))
        assert_equal(42, status.exitstatus, msg)
        assert_equal("ok\n", `#{exename} /c echo ok`, msg)
        assert_equal("ok\n", IO.popen("#{exename} /c echo ok", &:read), msg)
        assert_equal("ok\n", IO.popen(%W"#{exename} /c echo ok", &:read), msg)
        File.binwrite("#{name}.txt", "ok")
        assert_equal("ok", `type #{name}.txt`)
      end
    end
  end if windows?

  def test_exec_nonascii
    bug12841 = '[ruby-dev:49838] [Bug #12841]'

    [
      "\u{7d05 7389}",
      "zuf\u{00E4}llige_\u{017E}lu\u{0165}ou\u{010D}k\u{00FD}_\u{10D2 10D0 10DB 10D4 10DD 10E0 10D4 10D1}_\u{0440 0430 0437 043B 043E 0433 0430}_\u{548C 65B0 52A0 5761 4EE5 53CA 4E1C}",
      "c\u{1EE7}a",
    ].each do |arg|
      begin
        arg = arg.encode(Encoding.find("locale"))
      rescue
      else
        assert_in_out_err([], "#{<<-"begin;"}\n#{<<-"end;"}", [arg], [], bug12841)
        begin;
          arg = "#{arg.b}".force_encoding("#{arg.encoding.name}")
          exec(ENV["COMSPEC"]||"cmd.exe", "/c", "echo", arg)
        end;
      end
    end
  end if windows?

  def test_clock_gettime
    t1 = Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)
    t2 = Time.now; t2 = t2.tv_sec * 1000000000 + t2.tv_nsec
    t3 = Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)
    assert_operator(t1, :<=, t2)
    assert_operator(t2, :<=, t3)
    assert_raise(Errno::EINVAL) { Process.clock_gettime(:foo) }
  end

  def test_clock_gettime_unit
    t0 = Time.now.to_f
    [
      [:nanosecond,  1_000_000_000],
      [:microsecond, 1_000_000],
      [:millisecond, 1_000],
      [:second, 1],
      [:float_microsecond, 1_000_000.0],
      [:float_millisecond, 1_000.0],
      [:float_second, 1.0],
      [nil, 1.0],
      [:foo],
    ].each do |unit, num|
      unless num
        assert_raise(ArgumentError){ Process.clock_gettime(Process::CLOCK_REALTIME, unit) }
        next
      end
      t1 = Process.clock_gettime(Process::CLOCK_REALTIME, unit)
      assert_kind_of num.integer? ? Integer : num.class, t1, [unit, num].inspect
      assert_in_delta t0, t1/num, 1, [unit, num].inspect
    end
  end

  def test_clock_gettime_constants
    Process.constants.grep(/\ACLOCK_/).each {|n|
      c = Process.const_get(n)
      begin
        t = Process.clock_gettime(c)
      rescue Errno::EINVAL
        next
      end
      assert_kind_of(Float, t, "Process.clock_gettime(Process::#{n})")
    }
  end

  def test_clock_gettime_GETTIMEOFDAY_BASED_CLOCK_REALTIME
    n = :GETTIMEOFDAY_BASED_CLOCK_REALTIME
    begin
      t = Process.clock_gettime(n)
    rescue Errno::EINVAL
      return
    end
    assert_kind_of(Float, t, "Process.clock_gettime(:#{n})")
  end

  def test_clock_gettime_TIME_BASED_CLOCK_REALTIME
    n = :TIME_BASED_CLOCK_REALTIME
    t = Process.clock_gettime(n)
    assert_kind_of(Float, t, "Process.clock_gettime(:#{n})")
  end

  def test_clock_gettime_TIMES_BASED_CLOCK_MONOTONIC
    n = :TIMES_BASED_CLOCK_MONOTONIC
    begin
      t = Process.clock_gettime(n)
    rescue Errno::EINVAL
      return
    end
    assert_kind_of(Float, t, "Process.clock_gettime(:#{n})")
  end

  def test_clock_gettime_GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID
    n = :GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID
    begin
      t = Process.clock_gettime(n)
    rescue Errno::EINVAL
      return
    end
    assert_kind_of(Float, t, "Process.clock_gettime(:#{n})")
  end

  def test_clock_gettime_TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID
    n = :TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID
    begin
      t = Process.clock_gettime(n)
    rescue Errno::EINVAL
      return
    end
    assert_kind_of(Float, t, "Process.clock_gettime(:#{n})")
  end

  def test_clock_gettime_CLOCK_BASED_CLOCK_PROCESS_CPUTIME_ID
    n = :CLOCK_BASED_CLOCK_PROCESS_CPUTIME_ID
    t = Process.clock_gettime(n)
    assert_kind_of(Float, t, "Process.clock_gettime(:#{n})")
  end

  def test_clock_gettime_MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC
    n = :MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC
    begin
      t = Process.clock_gettime(n)
    rescue Errno::EINVAL
      return
    end
    assert_kind_of(Float, t, "Process.clock_gettime(:#{n})")
  end

  def test_clock_getres
    r = Process.clock_getres(Process::CLOCK_REALTIME, :nanosecond)
  rescue Errno::EINVAL
  else
    assert_kind_of(Integer, r)
    assert_raise(Errno::EINVAL) { Process.clock_getres(:foo) }
  end

  def test_clock_getres_constants
    Process.constants.grep(/\ACLOCK_/).each {|n|
      c = Process.const_get(n)
      begin
        t = Process.clock_getres(c)
      rescue Errno::EINVAL
        next
      end
      assert_kind_of(Float, t, "Process.clock_getres(Process::#{n})")
    }
  end

  def test_clock_getres_GETTIMEOFDAY_BASED_CLOCK_REALTIME
    n = :GETTIMEOFDAY_BASED_CLOCK_REALTIME
    begin
      t = Process.clock_getres(n)
    rescue Errno::EINVAL
      return
    end
    assert_kind_of(Float, t, "Process.clock_getres(:#{n})")
    assert_equal(1000, Process.clock_getres(n, :nanosecond))
  end

  def test_clock_getres_TIME_BASED_CLOCK_REALTIME
    n = :TIME_BASED_CLOCK_REALTIME
    t = Process.clock_getres(n)
    assert_kind_of(Float, t, "Process.clock_getres(:#{n})")
    assert_equal(1000000000, Process.clock_getres(n, :nanosecond))
  end

  def test_clock_getres_TIMES_BASED_CLOCK_MONOTONIC
    n = :TIMES_BASED_CLOCK_MONOTONIC
    begin
      t = Process.clock_getres(n)
    rescue Errno::EINVAL
      return
    end
    assert_kind_of(Float, t, "Process.clock_getres(:#{n})")
    f = Process.clock_getres(n, :hertz)
    assert_equal(0, f - f.floor)
  end

  def test_clock_getres_GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID
    n = :GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID
    begin
      t = Process.clock_getres(n)
    rescue Errno::EINVAL
      return
    end
    assert_kind_of(Float, t, "Process.clock_getres(:#{n})")
    assert_equal(1000, Process.clock_getres(n, :nanosecond))
  end

  def test_clock_getres_TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID
    n = :TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID
    begin
      t = Process.clock_getres(n)
    rescue Errno::EINVAL
      return
    end
    assert_kind_of(Float, t, "Process.clock_getres(:#{n})")
    f = Process.clock_getres(n, :hertz)
    assert_equal(0, f - f.floor)
  end

  def test_clock_getres_CLOCK_BASED_CLOCK_PROCESS_CPUTIME_ID
    n = :CLOCK_BASED_CLOCK_PROCESS_CPUTIME_ID
    t = Process.clock_getres(n)
    assert_kind_of(Float, t, "Process.clock_getres(:#{n})")
    f = Process.clock_getres(n, :hertz)
    assert_equal(0, f - f.floor)
  end

  def test_clock_getres_MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC
    n = :MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC
    begin
      t = Process.clock_getres(n)
    rescue Errno::EINVAL
      return
    end
    assert_kind_of(Float, t, "Process.clock_getres(:#{n})")
  end

  def test_deadlock_by_signal_at_forking
    assert_separately(%W(--disable=gems - #{RUBY}), <<-INPUT, timeout: 100)
      ruby = ARGV.shift
      GC.start # reduce garbage
      GC.disable # avoid triggering CoW after forks
      trap(:QUIT) {}
      parent = $$
      100.times do |i|
        pid = fork {Process.kill(:QUIT, parent)}
        IO.popen([ruby, -'--disable=gems'], -'r+'){}
        Process.wait(pid)
      end
    INPUT
  end if defined?(fork)

  def test_process_detach
    pid = fork {}
    th = Process.detach(pid)
    assert_equal pid, th.pid
    status = th.value
    assert_predicate status, :success?
  end if defined?(fork)

  def test_kill_at_spawn_failure
    bug11166 = '[ruby-core:69304] [Bug #11166]'
    th = nil
    x = with_tmpchdir {|d|
      prog = "#{d}/notexist"
      q = Thread::Queue.new
      th = Thread.start {system(prog);q.push(nil);sleep}
      q.pop
      th.kill
      th.join(0.1)
    }
    assert_equal(th, x, bug11166)
  end if defined?(fork)

  def test_exec_fd_3_redirect
    # ensure we can redirect anything to fd=3 in a child process.
    # fd=3 is a commonly reserved FD for the timer thread pipe in the
    # parent, but fd=3 is the first FD used by the sd_listen_fds function
    # for systemd
    assert_separately(['-', RUBY], <<-INPUT, timeout: 60)
      ruby = ARGV.shift
      begin
        a = IO.pipe
        b = IO.pipe
        pid = fork do
          exec ruby, '-e', 'print IO.for_fd(3).read(1)', 3 => a[0], 1 => b[1]
        end
        b[1].close
        a[0].close
        a[1].write('.')
        assert_equal ".", b[0].read(1)
      ensure
        Process.wait(pid) if pid
        a.each(&:close) if a
        b.each(&:close) if b
      end
    INPUT
  end if defined?(fork)

  def test_exec_close_reserved_fd
    cmd = ".#{File::ALT_SEPARATOR || File::SEPARATOR}bug11353"
    with_tmpchdir {
      (3..6).each do |i|
        ret = run_in_child(<<-INPUT)
          begin
            $VERBOSE = nil
            Process.exec('#{cmd}', 'dummy', #{i} => :close)
          rescue SystemCallError
          end
        INPUT
        assert_equal(0, ret)
      end
    }
  end

  def test_signals_work_after_exec_fail
    r, w = IO.pipe
    pid = status = nil
    EnvUtil.timeout(30) do
      pid = fork do
        r.close
        begin
          trap(:USR1) { w.syswrite("USR1\n"); exit 0 }
          exec "/path/to/non/existent/#$$/#{rand}.ex"
        rescue SystemCallError
          w.syswrite("exec failed\n")
        end
        sleep
        exit 1
      end
      w.close
      assert_equal "exec failed\n", r.gets
      Process.kill(:USR1, pid)
      assert_equal "USR1\n", r.gets
      assert_nil r.gets
      _, status = Process.waitpid2(pid)
    end
    assert_predicate status, :success?
  rescue Timeout::Error
    begin
      Process.kill(:KILL, pid)
    rescue Errno::ESRCH
    end
    raise
  ensure
    w.close if w
    r.close if r
  end if defined?(fork)

  def test_threading_works_after_exec_fail
    r, w = IO.pipe
    pid = status = nil
    EnvUtil.timeout(90) do
      pid = fork do
        r.close
        begin
          exec "/path/to/non/existent/#$$/#{rand}.ex"
        rescue SystemCallError
          w.syswrite("exec failed\n")
        end
        q = Queue.new
        th1 = Thread.new { i = 0; i += 1 while q.empty?; i }
        th2 = Thread.new { j = 0; j += 1 while q.empty? && Thread.pass.nil?; j }
        sleep 0.5
        q << true
        w.syswrite "#{th1.value} #{th2.value}\n"
      end
      w.close
      assert_equal "exec failed\n", r.gets
      vals = r.gets.split.map!(&:to_i)
      assert_operator vals[0], :>, vals[1], vals.inspect
      _, status = Process.waitpid2(pid)
    end
    assert_predicate status, :success?
  rescue Timeout::Error
    begin
      Process.kill(:KILL, pid)
    rescue Errno::ESRCH
    end
    raise
  ensure
    w.close if w
    r.close if r
  end if defined?(fork)

  def test_rescue_exec_fail
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      assert_raise(Errno::ENOENT) do
        exec("", in: "")
      end
    end;
  end

  def test_many_args
    bug11418 = '[ruby-core:70251] [Bug #11418]'
    assert_in_out_err([], <<-"end;", ["x"]*256, [], bug11418, timeout: 60)
      bin = "#{EnvUtil.rubybin}"
      args = Array.new(256) {"x"}
      GC.stress = true
      system(bin, "--disable=gems", "-w", "-e", "puts ARGV", *args)
    end;
  end

  def test_to_hash_on_arguments
    all_assertions do |a|
      %w[Array String].each do |type|
        a.for(type) do
          assert_separately(['-', EnvUtil.rubybin], <<~"END;")
          class #{type}
            def to_hash
              raise "[Bug-12355]: #{type}#to_hash is called"
            end
          end
          ex = ARGV[0]
          assert_equal(true, system([ex, ex], "-e", ""))
          END;
        end
      end
    end
  end

  def test_forked_child_handles_signal
    skip "fork not supported" unless Process.respond_to?(:fork)
    assert_normal_exit(<<-"end;", '[ruby-core:82883] [Bug #13916]')
      require 'timeout'
      pid = fork { sleep }
      Process.kill(:TERM, pid)
      assert_equal pid, Timeout.timeout(30) { Process.wait(pid) }
    end;
  end

  if Process.respond_to?(:initgroups)
    def test_initgroups
      assert_raise(ArgumentError) do
        Process.initgroups("\0", 0)
      end
    end
  end

  def test_last_status
    Process.wait spawn(RUBY, "-e", "exit 13")
    assert_same(Process.last_status, $?)
  end

  def test_exec_failure_leaves_no_child
    assert_raise(Errno::ENOENT) do
      spawn('inexistent_command')
    end
    assert_empty(Process.waitall)
  end
end
