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
          if msg.empty?
            full_message = build_message(message, "pid ? killed by ?",
                                         pid,
                                         AssertionMessage::Literal.new(sigdesc))
          else
            msg << "\n" if /\n\z/ !~ msg
            full_message = build_message(message, "pid ? killed by ?\n?",
                                         pid,
                                         AssertionMessage::Literal.new(sigdesc),
                                         AssertionMessage::Literal.new(msg.gsub(/^/, '| ')))
          end
        end
        assert_block(full_message) { !status.signaled? }
      ensure
        in_c.close if in_c && !in_c.closed?
        in_p.close if in_p && !in_p.closed?
        out_c.close if out_c && !out_c.closed?
        out_p.close if out_p && !out_p.closed?
      end
    end
  end
end

