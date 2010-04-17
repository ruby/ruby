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
    if defined?(RbConfig.ruby)
      RbConfig.ruby
    else
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

  def invoke_ruby(args, stdin_data="", capture_stdout=false, capture_stderr=false, opt={})
    begin
      in_c, in_p = IO.pipe
      out_p, out_c = IO.pipe if capture_stdout
      err_p, err_c = IO.pipe if capture_stderr
      c = "C"
      env = {}
      LANG_ENVS.each {|lc| env[lc], ENV[lc] = ENV[lc], c}
      opt = opt.dup
      opt[:in] = in_c
      opt[:out] = out_c if capture_stdout
      opt[:err] = err_c if capture_stderr
      pid = spawn(EnvUtil.rubybin, *args, opt)
      in_c.close
      out_c.close if capture_stdout
      err_c.close if capture_stderr
      in_p.write stdin_data.to_str
      in_p.close
      th_stdout = Thread.new { out_p.read } if capture_stdout
      th_stderr = Thread.new { err_p.read } if capture_stderr
      if (!capture_stdout || th_stdout.join(10)) && (!capture_stderr || th_stderr.join(10))
        stdout = th_stdout.value if capture_stdout
        stderr = th_stderr.value if capture_stderr
      else
        raise Timeout::Error
      end
      out_p.close if capture_stdout
      err_p.close if capture_stderr
      Process.wait pid
      status = $?
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
    return stdout, stderr, status
  end
  module_function :invoke_ruby

  def verbose_warning
    class << (stderr = "")
      alias write <<
    end
    stderr, $stderr, verbose, $VERBOSE = $stderr, stderr, $VERBOSE, true
    yield stderr
  ensure
    stderr, $stderr, $VERBOSE = $stderr, stderr, verbose
    return stderr
  end
  module_function :verbose_warning
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

      def assert_in_out_err(args, test_stdin = "", test_stdout = [], test_stderr = [], message = nil, opt={})
        stdout, stderr, status = EnvUtil.invoke_ruby(args, test_stdin, true, true, opt)
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
      end

      def assert_ruby_status(args, test_stdin="", message=nil, opt={})
        stdout, stderr, status = EnvUtil.invoke_ruby(args, test_stdin, false, false, opt)
        m = message ? "#{message} (#{status.inspect})" : "ruby exit status is not success: #{status.inspect}"
        assert(status.success?, m)
      end

    end
  end
end

begin
  require 'rbconfig'
rescue LoadError
else
  module RbConfig
    @ruby = EnvUtil.rubybin
    class << self
      undef ruby if method_defined?(:ruby)
      attr_reader :ruby
    end
    dir = File.dirname(ruby)
    name = File.basename(ruby, CONFIG['EXEEXT'])
    CONFIG['bindir'] = dir
    CONFIG['ruby_install_name'] = name
    CONFIG['RUBY_INSTALL_NAME'] = name
    Gem::ConfigMap[:bindir] = dir
  end
end
