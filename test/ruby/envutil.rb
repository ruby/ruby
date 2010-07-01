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

  def invoke_ruby(args, stdin_data="", capture_stdout=false, capture_stderr=false, opt={})
    in_c, in_p = IO.pipe
    out_p, out_c = IO.pipe if capture_stdout
    err_p, err_c = IO.pipe if capture_stderr
    opt = opt.dup
    opt[:in] = in_c
    opt[:out] = out_c if capture_stdout
    opt[:err] = err_c if capture_stderr
    if enc = opt.delete(:encoding)
      out_p.set_encoding(enc) if out_p
      err_p.set_encoding(enc) if err_p
    end
    c = "C"
    child_env = {}
    LANG_ENVS.each {|lc| child_env[lc] = c}
    if Array === args and Hash === args.first
      child_env.update(args.shift)
    end
    args = [args] if args.kind_of?(String)
    pid = spawn(child_env, EnvUtil.rubybin, *args, opt)
    in_c.close
    out_c.close if capture_stdout
    err_c.close if capture_stderr
    if block_given?
      return yield in_p, out_p, err_p
    else
      th_stdout = Thread.new { out_p.read } if capture_stdout
      th_stderr = Thread.new { err_p.read } if capture_stderr
      in_p.write stdin_data.to_str
      in_p.close
      timeout = opt.fetch(:timeout, 10)
      if (!capture_stdout || th_stdout.join(timeout)) && (!capture_stderr || th_stderr.join(timeout))
        stdout = th_stdout.value if capture_stdout
        stderr = th_stderr.value if capture_stderr
      else
        raise Timeout::Error
      end
      out_p.close if capture_stdout
      err_p.close if capture_stderr
      Process.wait pid
      status = $?
      return stdout, stderr, status
    end
  ensure
    [in_c, in_p, out_c, out_p, err_c, err_p].each do |io|
      io.close if io && !io.closed?
    end
    [th_stdout, th_stderr].each do |th|
      (th.kill; th.join) if th
    end
  end
  module_function :invoke_ruby

  alias rubyexec invoke_ruby
  class << self
    alias rubyexec invoke_ruby
  end

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

  def under_gc_stress
    stress, GC.stress = GC.stress, true
    yield
  ensure
    GC.stress = stress
  end
  module_function :under_gc_stress
end

module Test
  module Unit
    module Assertions
      public
      def assert_normal_exit(testsrc, message = '', opt = {})
        stdout, stderr, status = EnvUtil.invoke_ruby(%W'-W0', testsrc, true, true, opt)
        pid = status.pid
        faildesc = proc do
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
          full_message
        end
        assert_block(faildesc) { !status.signaled? }
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
          status
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
    Gem::ConfigMap[:bindir] = dir if defined?(Gem)
  end
end
