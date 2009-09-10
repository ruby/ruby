require "open3"
require "timeout"

module EnvUtil
  def rubybin
    unless ENV["RUBYOPT"]

    end
    if ruby = ENV["RUBY"]
      return ruby
    end
    ruby = "ruby"
    rubyexe = ruby+".exe"
    3.times do
      if File.exist? ruby and File.executable? ruby and !File.directory? ruby
        return File.expand_path(ruby)
      end
      if File.exist? rubyexe and File.executable? rubyexe
        return File.expand_path(rubyexe)
      end
      ruby = File.join("..", ruby)
    end
    begin
      require "rbconfig"
      File.join(
        RbConfig::CONFIG["bindir"],
	RbConfig::CONFIG["ruby_install_name"] + RbConfig::CONFIG["EXEEXT"]
      )
    rescue LoadError
      "ruby"
    end
  end
  module_function :rubybin

  LANG_ENVS = %w"LANG LC_ALL LC_CTYPE"
  def rubyexec(*args)
    ruby = EnvUtil.rubybin
    c = "C"
    env = {}
    LANG_ENVS.each {|lc| env[lc], ENV[lc] = ENV[lc], c}
    stdin = stdout = stderr = nil
    Timeout.timeout(10) do
      stdin, stdout, stderr = Open3.popen3(*([ruby] + args))
      env.each_pair {|lc, v|
        if v
          ENV[lc] = v
        else
          ENV.delete(lc)
        end
      }
      env = nil
      yield(stdin, stdout, stderr)
    end

  ensure
    env.each_pair {|lc, v|
      if v
        ENV[lc] = v
      else
        ENV.delete(lc)
      end
    } if env
    stdin .close unless !stdin  || stdin .closed?
    stdout.close unless !stdout || stdout.closed?
    stderr.close unless !stderr || stderr.closed?
  end
  module_function :rubyexec
end

module Test
  module Unit
    module Assertions
      public
      def assert_normal_exit(testsrc, message = '')
        in_c, in_p = IO.pipe
        out_p, out_c = IO.pipe
        pid = spawn(EnvUtil.rubybin, '-W0', STDIN=>in_c, STDOUT=>out_c, STDERR=>out_c)
        in_c.close
        out_c.close
        in_p.write testsrc
        in_p.close
        msg = out_p.read
        out_p.close
        Process.wait pid
        status = $?
        faildesc = nil
        if status.signaled?
          signo = status.termsig
          signame = Signal.list.invert[signo]
          sigdesc = "signal #{signo}"
          if signame
            sigdesc = "SIG#{signame} (#{sigdesc})"
          end
          if status.coredump?
            sigdesc << " (core dumped)"
          end
          full_message = ''
          if !message.empty?
            full_message << message << "\n"
          end
          if msg.empty?
            full_message << "pid #{pid} killed by #{sigdesc}"
          else
            msg << "\n" if /\n\z/ !~ msg
            full_message << "pid #{pid} killed by #{sigdesc}\n#{msg.gsub(/^/, '| ')}"
          end
        end
        assert_block(full_message) { !status.signaled? }
      ensure
        in_c.close if in_c && !in_c.closed?
        in_p.close if in_p && !in_p.closed?
        out_c.close if out_c && !out_c.closed?
        out_p.close if out_p && !out_p.closed?
      end

      LANG_ENVS = %w"LANG LC_ALL LC_CTYPE"
      def assert_in_out_err(args, test_stdin = "", test_stdout = "", test_stderr = "", message = nil)
        in_c, in_p = IO.pipe
        out_p, out_c = IO.pipe
        err_p, err_c = IO.pipe
        c = "C"
        env = {}
        LANG_ENVS.each {|lc| env[lc], ENV[lc] = ENV[lc], c}
        pid = spawn(EnvUtil.rubybin, *args, STDIN=>in_c, STDOUT=>out_c, STDERR=>err_c)
        in_c.close
        out_c.close
        err_c.close
        in_p.write test_stdin
        in_p.close
        th_stdout = Thread.new { out_p.read }
        th_stderr = Thread.new { err_p.read }
        if th_stdout.join(10) && th_stderr.join(10)
          stdout = th_stdout.value
          stderr = th_stderr.value
        else
          flunk("timeout")
        end
        out_p.close
        err_p.close
        Process.wait pid
        if block_given?
          yield(stdout.lines.map {|l| l.chomp }, stderr.lines.map {|l| l.chomp })
        else
          if test_stdout.is_a?(Regexp)
            assert_match(test_stdout, stdout, message)
          else
            assert_equal(test_stdout, stdout.lines.map {|l| l.chomp }, message)
          end
          if test_stderr.is_a?(Regexp)
            assert_match(test_stderr, stderr, message)
          else
            assert_equal(test_stderr, stderr.lines.map {|l| l.chomp }, message)
          end
        end
      ensure
        env.each_pair {|lc, v|
          if v
            ENV[lc] = v
          else
            ENV.delete(lc)
          end
        } if env
        in_c.close if in_c && !in_c.closed?
        in_p.close if in_p && !in_p.closed?
        out_c.close if out_c && !out_c.closed?
        out_p.close if out_p && !out_p.closed?
        err_c.close if err_c && !err_c.closed?
        err_p.close if err_p && !err_p.closed?
        (th_stdout.kill; th_stdout.join) if th_stdout
        (th_stderr.kill; th_stderr.join) if th_stderr
      end
    end
  end
end

