# -*- coding: us-ascii -*-
require "open3"
require "timeout"
require "test/unit"

module EnvUtil
  def rubybin
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

  def invoke_ruby(args, stdin_data = "", capture_stdout = false, capture_stderr = false,
                  encoding: nil, timeout: 10, reprieve: 1,
                  stdout_filter: nil, stderr_filter: nil,
                  **opt)
    in_c, in_p = IO.pipe
    out_p, out_c = IO.pipe if capture_stdout
    err_p, err_c = IO.pipe if capture_stderr && capture_stderr != :merge_to_stdout
    opt[:in] = in_c
    opt[:out] = out_c if capture_stdout
    opt[:err] = capture_stderr == :merge_to_stdout ? out_c : err_c if capture_stderr
    if encoding
      out_p.set_encoding(encoding) if out_p
      err_p.set_encoding(encoding) if err_p
    end
    c = "C"
    child_env = {}
    LANG_ENVS.each {|lc| child_env[lc] = c}
    if Array === args and Hash === args.first
      child_env.update(args.shift)
    end
    args = [args] if args.kind_of?(String)
    pid = spawn(child_env, EnvUtil.rubybin, *args, **opt)
    in_c.close
    out_c.close if capture_stdout
    err_c.close if capture_stderr && capture_stderr != :merge_to_stdout
    if block_given?
      return yield in_p, out_p, err_p, pid
    else
      th_stdout = Thread.new { out_p.read } if capture_stdout
      th_stderr = Thread.new { err_p.read } if capture_stderr && capture_stderr != :merge_to_stdout
      in_p.write stdin_data.to_str unless stdin_data.empty?
      in_p.close
      if (!th_stdout || th_stdout.join(timeout)) && (!th_stderr || th_stderr.join(timeout))
        stdout = th_stdout.value if capture_stdout
        stderr = th_stderr.value if capture_stderr && capture_stderr != :merge_to_stdout
      else
        signal = /mswin|mingw/ =~ RUBY_PLATFORM ? :KILL : :TERM
        begin
          Process.kill signal, pid
          Timeout.timeout((reprieve unless signal == :KILL)) do
            Process.wait(pid)
          end
        rescue Errno::ESRCH
          break
        rescue Timeout::Error
          raise if signal == :KILL
          signal = :KILL
        else
          break
        end while true
        bt = caller_locations
        raise Timeout::Error, "execution of #{bt.shift.label} expired", bt.map(&:to_s)
      end
      out_p.close if capture_stdout
      err_p.close if capture_stderr && capture_stderr != :merge_to_stdout
      Process.wait pid
      status = $?
      stdout = stdout_filter.call(stdout) if stdout_filter
      stderr = stderr_filter.call(stderr) if stderr_filter
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

  def under_gc_stress(stress = true)
    stress, GC.stress = GC.stress, stress
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

  def labeled_module(name, &block)
    Module.new do
      singleton_class.class_eval {define_method(:to_s) {name}; alias inspect to_s}
      class_eval(&block) if block
    end
  end
  module_function :labeled_module

  def labeled_class(name, superclass = Object, &block)
    Class.new(superclass) do
      singleton_class.class_eval {define_method(:to_s) {name}; alias inspect to_s}
      class_eval(&block) if block
    end
  end
  module_function :labeled_class

  if /darwin/ =~ RUBY_PLATFORM
    DIAGNOSTIC_REPORTS_PATH = File.expand_path("~/Library/Logs/DiagnosticReports")
    DIAGNOSTIC_REPORTS_TIMEFORMAT = '%Y-%m-%d-%H%M%S'
    def self.diagnostic_reports(signame, cmd, pid, now)
      return unless %w[ABRT QUIT SEGV ILL].include?(signame)
      cmd = File.basename(cmd)
      path = DIAGNOSTIC_REPORTS_PATH
      timeformat = DIAGNOSTIC_REPORTS_TIMEFORMAT
      pat = "#{path}/#{cmd}_#{now.strftime(timeformat)}[-_]*.crash"
      first = true
      30.times do
        first ? (first = false) : sleep(0.1)
        Dir.glob(pat) do |name|
          log = File.read(name) rescue next
          if /\AProcess:\s+#{cmd} \[#{pid}\]$/ =~ log
            File.unlink(name)
            File.unlink("#{path}/.#{File.basename(name)}.plist") rescue nil
            return log
          end
        end
      end
      nil
    end
  else
    def self.diagnostic_reports(signame, cmd, pid, now)
    end
  end
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
        code.force_encoding(Encoding::UTF_8)
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

      def assert_normal_exit(testsrc, message = '', child_env: nil, **opt)
        assert_valid_syntax(testsrc, caller_locations(1, 1)[0])
        if child_env
          child_env = [child_env]
        else
          child_env = []
        end
        out, _, status = EnvUtil.invoke_ruby(child_env + %W'-W0', testsrc, true, :merge_to_stdout, **opt)
        assert !status.signaled?, FailDesc[status, message, out]
      end

      FailDesc = proc do |status, message = "", out = ""|
        pid = status.pid
        now = Time.now
        faildesc = proc do
          if signo = status.termsig
            signame = Signal.signame(signo)
            sigdesc = "signal #{signo}"
          end
          log = EnvUtil.diagnostic_reports(signame, EnvUtil.rubybin, pid, now)
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
          if log
            full_message << "\n#{log.gsub(/^/, '| ')}"
          end
          full_message
        end
        faildesc
      end

      def assert_in_out_err(args, test_stdin = "", test_stdout = [], test_stderr = [], message = nil, **opt)
        stdout, stderr, status = EnvUtil.invoke_ruby(args, test_stdin, true, true, **opt)
        if signo = status.termsig
          EnvUtil.diagnostic_reports(Signal.signame(signo), EnvUtil.rubybin, status.pid, Time.now)
        end
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

      def assert_ruby_status(args, test_stdin="", message=nil, **opt)
        out, _, status = EnvUtil.invoke_ruby(args, test_stdin, true, :merge_to_stdout, **opt)
        assert(!status.signaled?, FailDesc[status, message, out])
        message ||= "ruby exit status is not success:"
        assert(status.success?, "#{message} (#{status.inspect})")
      end

      ABORT_SIGNALS = Signal.list.values_at(*%w"ILL ABRT BUS SEGV")

      def assert_separately(args, file = nil, line = nil, src, ignore_stderr: nil, **opt)
        unless file and line
          loc, = caller_locations(1,1)
          file ||= loc.path
          line ||= loc.lineno
        end
        line -= 2
        src = <<eom
# -*- coding: #{src.encoding}; -*-
  require #{__dir__.dump}'/envutil';include Test::Unit::Assertions
  END {
    puts [Marshal.dump($!)].pack('m'), "assertions=\#{self._assertions}"
  }
#{src}
  class Test::Unit::Runner
    @@stop_auto_run = true
  end
eom
        args = args.dup
        args.insert((Hash === args.first ? 1 : 0), "--disable=gems", *$:.map {|l| "-I#{l}"})
        stdout, stderr, status = EnvUtil.invoke_ruby(args, src, true, true, **opt)
        abort = status.coredump? || (status.signaled? && ABORT_SIGNALS.include?(status.termsig))
        assert(!abort, FailDesc[status, nil, stderr])
        self._assertions += stdout[/^assertions=(\d+)/, 1].to_i
        begin
          res = Marshal.load(stdout.unpack("m")[0])
        rescue => marshal_error
          ignore_stderr = nil
        end
        if res
          if bt = res.backtrace
            bt.each do |l|
              l.sub!(/\A-:(\d+)/){"#{file}:#{line + $1.to_i}"}
            end
          end
          raise res
        end

        # really is it succeed?
        unless ignore_stderr
          # the body of assert_separately must not output anything to detect errror
          assert_equal("", stderr, "assert_separately failed with error message")
        end
        assert_equal(0, status, "assert_separately failed: '#{stderr}'")
        raise marshal_error if marshal_error
      end

      def assert_warning(pat, msg = nil)
        stderr = EnvUtil.verbose_warning { yield }
        msg = message(msg) {diff stderr, pat}
        assert(pat === stderr, msg)
      end

      def assert_warn(*args)
        assert_warning(*args) {$VERBOSE = false; yield}
      end

      def assert_no_memory_leak(args, prepare, code, message=nil, limit: 1.5, rss: false, **opt)
        require_relative 'memory_status'
        token = "\e[7;1m#{$$.to_s}:#{Time.now.strftime('%s.%L')}:#{rand(0x10000).to_s(16)}:\e[m"
        token_dump = token.dump
        token_re = Regexp.quote(token)
        envs = args.shift if Array === args and Hash === args.first
        args = [
          "--disable=gems",
          "-r", File.expand_path("../memory_status", __FILE__),
          *args,
          "-v", "-",
        ]
        args.unshift(envs) if envs
        cmd = [
          'END {STDERR.puts '"#{token_dump}"'"FINAL=#{Memory::Status.new}"}',
          prepare,
          'STDERR.puts('"#{token_dump}"'"START=#{$initial_status = Memory::Status.new}")',
          '$initial_size = $initial_status.size',
          code,
          'GC.start',
        ].join("\n")
        _, err, status = EnvUtil.invoke_ruby(args, cmd, true, true, **opt)
        before = err.sub!(/^#{token_re}START=(\{.*\})\n/, '') && Memory::Status.parse($1)
        after = err.sub!(/^#{token_re}FINAL=(\{.*\})\n/, '') && Memory::Status.parse($1)
        assert_equal([true, ""], [status.success?, err], message)
        ([:size, (rss && :rss)] & after.members).each do |n|
          b = before[n]
          a = after[n]
          next unless a > 0 and b > 0
          assert_operator(a.fdiv(b), :<, limit, message(message) {"#{n}: #{b} => #{a}"})
        end
      end

      def assert_is_minus_zero(f)
        assert(1.0/f == -Float::INFINITY, "#{f} is not -0.0")
      end

      def assert_file
        AssertFile
      end

      # threads should respond to shift method.
      # Array and Queue can be used.
      def assert_join_threads(threads, message = nil)
        errs = []
        values = []
        while th = threads.shift
          begin
            values << th.value
          rescue Exception
            errs << $!
          end
        end
        if !errs.empty?
          msg = errs.map {|err|
            err.backtrace.map.with_index {|line, i|
              if i == 0
                "#{line}: #{err.message} (#{err.class})"
              else
                "\tfrom #{line}"
              end
            }.join("\n")
          }.join("\n---\n")
          if message
            msg = "#{message}\n#{msg}"
          end
          raise MiniTest::Assertion, msg
        end
        values
      end

      class << (AssertFile = Struct.new(:failure_message).new)
        include Assertions
        def assert_file_predicate(predicate, *args)
          if /\Anot_/ =~ predicate
            predicate = $'
            neg = " not"
          end
          result = File.__send__(predicate, *args)
          result = !result if neg
          mesg = "Expected file " << args.shift.inspect
          mesg << "#{neg} to be #{predicate}"
          mesg << mu_pp(args).sub(/\A\[(.*)\]\z/m, '(\1)') unless args.empty?
          mesg << " #{failure_message}" if failure_message
          assert(result, mesg)
        end
        alias method_missing assert_file_predicate

        def for(message)
          clone.tap {|a| a.failure_message = message}
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
