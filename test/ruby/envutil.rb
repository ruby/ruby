# -*- coding: us-ascii -*-
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
    err_p, err_c = IO.pipe if capture_stderr && capture_stderr != :merge_to_stdout
    opt = opt.dup
    opt[:in] = in_c
    opt[:out] = out_c if capture_stdout
    opt[:err] = capture_stderr == :merge_to_stdout ? out_c : err_c if capture_stderr
    if enc = opt.delete(:encoding)
      out_p.set_encoding(enc) if out_p
      err_p.set_encoding(enc) if err_p
    end
    timeout = opt.delete(:timeout) || 10
    reprieve = opt.delete(:reprieve) || 1
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
    err_c.close if capture_stderr && capture_stderr != :merge_to_stdout
    if block_given?
      return yield in_p, out_p, err_p, pid
    else
      th_stdout = Thread.new { out_p.read } if capture_stdout
      th_stderr = Thread.new { err_p.read } if capture_stderr && capture_stderr != :merge_to_stdout
      in_p.write stdin_data.to_str
      in_p.close
      if (!th_stdout || th_stdout.join(timeout)) && (!th_stderr || th_stderr.join(timeout))
        stdout = th_stdout.value if capture_stdout
        stderr = th_stderr.value if capture_stderr && capture_stderr != :merge_to_stdout
      else
        signal = /mswin|mingw/ =~ RUBY_PLATFORM ? :KILL : :TERM
        begin
          Process.kill signal, pid
        rescue Errno::ESRCH
          break
        else
        end until signal == :KILL or (sleep reprieve; signal = :KILL; false)
        raise Timeout::Error
      end
      out_p.close if capture_stdout
      err_p.close if capture_stderr && capture_stderr != :merge_to_stdout
      Process.wait pid
      status = $?
      return stdout, stderr, status
    end
  ensure
    [th_stdout, th_stderr].each do |th|
      th.kill if th
    end
    [in_c, in_p, out_c, out_p, err_c, err_p].each do |io|
      io.close if io && !io.closed?
    end
    [th_stdout, th_stderr].each do |th|
      th.join if th
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
    return $stderr
  ensure
    stderr, $stderr, $VERBOSE = $stderr, stderr, verbose
  end
  module_function :verbose_warning

  def suppress_warning
    verbose, $VERBOSE = $VERBOSE, nil
    yield
  ensure
    $VERBOSE = verbose
  end
  module_function :suppress_warning

  def under_gc_stress
    stress, GC.stress = GC.stress, true
    yield
  ensure
    GC.stress = stress
  end
  module_function :under_gc_stress

  def with_default_external(enc)
    verbose, $VERBOSE = $VERBOSE, nil
    origenc, Encoding.default_external = Encoding.default_external, enc
    $VERBOSE = verbose
    yield
  ensure
    verbose, $VERBOSE = $VERBOSE, nil
    Encoding.default_external = origenc
    $VERBOSE = verbose
  end
  module_function :with_default_external

  def with_default_internal(enc)
    verbose, $VERBOSE = $VERBOSE, nil
    origenc, Encoding.default_internal = Encoding.default_internal, enc
    $VERBOSE = verbose
    yield
  ensure
    verbose, $VERBOSE = $VERBOSE, nil
    Encoding.default_internal = origenc
    $VERBOSE = verbose
  end
  module_function :with_default_internal
end

module Test
  module Unit
    module Assertions
      public
      def assert_valid_syntax(code, fname = caller_locations(1, 1)[0], mesg = fname.to_s)
        code = code.dup.force_encoding("ascii-8bit")
        code.sub!(/\A(?:\xef\xbb\xbf)?(\s*\#.*$)*(\n)?/n) {
          "#$&#{"\n" if $1 && !$2}BEGIN{throw tag, :ok}\n"
        }
        code.force_encoding("us-ascii")
        verbose, $VERBOSE = $VERBOSE, nil
        yield if defined?(yield)
        case
        when Array === fname
          fname, line = *fname
        when defined?(fname.path) && defined?(fname.lineno)
          fname, line = fname.path, fname.lineno
        else
          line = 0
        end
        assert_nothing_raised(SyntaxError, mesg) do
          assert_equal(:ok, catch {|tag| eval(code, binding, fname, line)}, mesg)
        end
      ensure
        $VERBOSE = verbose
      end

      def assert_syntax_error(code, error, fname = caller_locations(1, 1)[0], mesg = fname.to_s)
        code = code.dup.force_encoding("ascii-8bit")
        code.sub!(/\A(?:\xef\xbb\xbf)?(\s*\#.*$)*(\n)?/n) {
          "#$&#{"\n" if $1 && !$2}BEGIN{throw tag, :ng}\n"
        }
        code.force_encoding("us-ascii")
        verbose, $VERBOSE = $VERBOSE, nil
        yield if defined?(yield)
        case
        when Array === fname
          fname, line = *fname
        when defined?(fname.path) && defined?(fname.lineno)
          fname, line = fname.path, fname.lineno
        else
          line = 0
        end
        e = assert_raise(SyntaxError, mesg) do
          catch {|tag| eval(code, binding, fname, line)}
        end
        assert_match(error, e.message, mesg)
      ensure
        $VERBOSE = verbose
      end

      def assert_normal_exit(testsrc, message = '', opt = {})
        assert_valid_syntax(testsrc, caller_locations(1, 1)[0])
        if opt.include?(:child_env)
          opt = opt.dup
          child_env = [opt.delete(:child_env)] || []
        else
          child_env = []
        end
        out, _, status = EnvUtil.invoke_ruby(child_env + %W'-W0', testsrc, true, :merge_to_stdout, opt)
        assert !status.signaled?, FailDesc[status, message, out]
      end

      FailDesc = proc do |status, message = "", out = ""|
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
          if message and !message.empty?
            full_message << message << "\n"
          end
          full_message << "pid #{pid} killed by #{sigdesc}"
          if out and !out.empty?
            full_message << "\n#{out.gsub(/^/, '| ')}"
            full_message << "\n" if /\n\z/ !~ full_message
          end
          full_message
        end
        faildesc
      end

      def assert_in_out_err(args, test_stdin = "", test_stdout = [], test_stderr = [], message = nil, opt={})
        stdout, stderr, status = EnvUtil.invoke_ruby(args, test_stdin, true, true, opt)
        if block_given?
          raise "test_stdout ignored, use block only or without block" if test_stdout != []
          raise "test_stderr ignored, use block only or without block" if test_stderr != []
          yield(stdout.lines.map {|l| l.chomp }, stderr.lines.map {|l| l.chomp }, status)
        else
          errs = []
          [[test_stdout, stdout], [test_stderr, stderr]].each do |exp, act|
            begin
              if exp.is_a?(Regexp)
                assert_match(exp, act, message)
              else
                assert_equal(exp, act.lines.map {|l| l.chomp }, message)
              end
            rescue MiniTest::Assertion => e
              errs << e.message
              message = nil
            end
          end
          raise MiniTest::Assertion, errs.join("\n---\n") unless errs.empty?
          status
        end
      end

      def assert_ruby_status(args, test_stdin="", message=nil, opt={})
        out, _, status = EnvUtil.invoke_ruby(args, test_stdin, true, :merge_to_stdout, opt)
        message ||= "ruby exit status is not success:"
        assert(status.success?, FailDesc[status, message, out])
      end

      ABORT_SIGNALS = Signal.list.values_at(*%w"ILL ABRT BUS SEGV")

      def assert_separately(args, file = nil, line = nil, src, **opt)
        unless file and line
          loc, = caller_locations(1,1)
          file ||= loc.path
          line ||= loc.lineno
        end
        src = <<eom
  require 'test/unit';include Test::Unit::Assertions;begin;#{src}
  ensure
    puts [Marshal.dump($!)].pack('m'), "assertions=\#{self._assertions}"
  end
  class Test::Unit::Runner
    @@stop_auto_run = true
  end
eom
        args = args.dup
        $:.each{|l| args.unshift "-I#{l}" }
        ignore_stderr = opt.delete(:ignore_stderr)
        stdout, stderr, status = EnvUtil.invoke_ruby(args, src, true, true, opt)
        abort = status.coredump? || (status.signaled? && ABORT_SIGNALS.include?(status.termsig))
        assert(!abort, FailDesc[status, stderr])
        self._assertions += stdout[/^assertions=(\d+)/, 1].to_i
        res = Marshal.load(stdout.unpack("m")[0])
        if res
          res.backtrace.each do |l|
            l.sub!(/\A-:(\d+)/){"#{file}:#{line + $1.to_i}"}
          end
          raise res
        end

        # really is it succeed?
        unless ignore_stderr
          # the body of assert_separately must not output anything to detect errror
          assert_equal("", stderr, "assert_separately failed with error message")
        end
        assert_equal(0, status, "assert_separately failed: '#{stderr}'")
      end

      def assert_warning(pat, message = nil)
        stderr = EnvUtil.verbose_warning { yield }
        message = ' "' + message + '"' if message
        msg = proc {"warning message #{stderr.inspect} is expected to match #{pat.inspect}#{message}"}
        assert(pat === stderr, msg)
      end

      def assert_warn(*args)
        assert_warning(*args) {$VERBOSE = false; yield}
      end

      def assert_no_memory_leak(args, prepare, code, message=nil, limit: 1.5)
        token = "\e[7;1m#{$$.to_s}:#{Time.now.strftime('%s.%L')}:#{rand(0x10000).to_s(16)}:\e[m"
        token_dump = token.dump
        token_re = Regexp.quote(token)
        args = [
          "--disable=gems",
          "-r", File.expand_path("../memory_status", __FILE__),
          *args,
          "-v", "-",
        ]
        cmd = [
          'END {STDERR.puts '"#{token_dump}"'"FINAL=#{Memory::Status.new.size}"}',
          prepare,
          'STDERR.puts('"#{token_dump}"'"START=#{$initial_size = Memory::Status.new.size}")',
          code,
        ].join("\n")
        _, err, status = EnvUtil.invoke_ruby(args, cmd, true, true)
        before = err.sub!(/^#{token_re}START=(\d+)\n/, '') && $1.to_i
        after = err.sub!(/^#{token_re}FINAL=(\d+)\n/, '') && $1.to_i
        assert_equal([true, ""], [status.success?, err], message)
        assert_operator(after.fdiv(before), :<, limit, message)
      end

      def assert_is_minus_zero(f)
        assert(1.0/f == -Float::INFINITY, "#{f} is not -0.0")
      end

      def assert_file
        AssertFile
      end

      class << (AssertFile = Struct.new(:message).new)
        include Assertions
        def assert_file_predicate(predicate, *args)
          if /\Anot_/ =~ predicate
            predicate = $'
            neg = " not"
          end
          result = File.__send__(predicate, *args)
          result = !result if neg
          mesg = "Expected file " << args.shift.inspect
          mesg << mu_pp(args) unless args.empty?
          mesg << "#{neg} to be #{predicate}"
          mesg << " #{message}" if message
          assert(result, mesg)
        end
        alias method_missing assert_file_predicate

        def for(message)
          clone.tap {|a| a.message = message}
        end
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
    Gem::ConfigMap[:bindir] = dir if defined?(Gem::ConfigMap)
  end
end
