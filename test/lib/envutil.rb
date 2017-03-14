# -*- coding: us-ascii -*-
# frozen_string_literal: false
require "open3"
require "timeout"
require_relative "find_executable"
begin
  require 'rbconfig'
rescue LoadError
end
begin
  require "rbconfig/sizeof"
rescue LoadError
end

module EnvUtil
  def rubybin
    if ruby = ENV["RUBY"]
      return ruby
    end
    ruby = "ruby"
    exeext = RbConfig::CONFIG["EXEEXT"]
    rubyexe = (ruby + exeext if exeext and !exeext.empty?)
    3.times do
      if File.exist? ruby and File.executable? ruby and !File.directory? ruby
        return File.expand_path(ruby)
      end
      if rubyexe and File.exist? rubyexe and File.executable? rubyexe
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

  DEFAULT_SIGNALS = Signal.list
  DEFAULT_SIGNALS.delete("TERM") if /mswin|mingw/ =~ RUBY_PLATFORM

  class << self
    attr_accessor :subprocess_timeout_scale
  end

  def invoke_ruby(args, stdin_data = "", capture_stdout = false, capture_stderr = false,
                  encoding: nil, timeout: 10, reprieve: 1, timeout_error: Timeout::Error,
                  stdout_filter: nil, stderr_filter: nil,
                  signal: :TERM,
                  rubybin: EnvUtil.rubybin,
                  **opt)
    if scale = EnvUtil.subprocess_timeout_scale
      timeout *= scale if timeout
      reprieve *= scale if reprieve
    end
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
    pid = spawn(child_env, rubybin, *args, **opt)
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
        timeout_error = nil
      else
        signals = Array(signal).select do |sig|
          DEFAULT_SIGNALS[sig.to_s] or
            DEFAULT_SIGNALS[Signal.signame(sig)] rescue false
        end
        signals |= [:ABRT, :KILL]
        case pgroup = opt[:pgroup]
        when 0, true
          pgroup = -pid
        when nil, false
          pgroup = pid
        end
        while signal = signals.shift
          begin
            Process.kill signal, pgroup
          rescue Errno::EINVAL
            next
          rescue Errno::ESRCH
            break
          end
          if signals.empty? or !reprieve
            Process.wait(pid)
          else
            begin
              Timeout.timeout(reprieve) {Process.wait(pid)}
            rescue Timeout::Error
            end
          end
        end
        status = $?
      end
      stdout = th_stdout.value if capture_stdout
      stderr = th_stderr.value if capture_stderr && capture_stderr != :merge_to_stdout
      out_p.close if capture_stdout
      err_p.close if capture_stderr && capture_stderr != :merge_to_stdout
      status ||= Process.wait2(pid)[1]
      stdout = stdout_filter.call(stdout) if stdout_filter
      stderr = stderr_filter.call(stderr) if stderr_filter
      if timeout_error
        bt = caller_locations
        msg = "execution of #{bt.shift.label} expired"
        msg = Test::Unit::Assertions::FailDesc[status, msg, [stdout, stderr].join("\n")].()
        raise timeout_error, msg, bt.map(&:to_s)
      end
      return stdout, stderr, status
    end
  ensure
    [th_stdout, th_stderr].each do |th|
      th.kill if th
    end
    [in_c, in_p, out_c, out_p, err_c, err_p].each do |io|
      io&.close
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

  def default_warning
    verbose, $VERBOSE = $VERBOSE, false
    yield
  ensure
    $VERBOSE = verbose
  end
  module_function :default_warning

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
    @ruby_install_name = RbConfig::CONFIG['RUBY_INSTALL_NAME']

    def self.diagnostic_reports(signame, pid, now)
      return unless %w[ABRT QUIT SEGV ILL TRAP].include?(signame)
      cmd = File.basename(rubybin)
      cmd = @ruby_install_name if "ruby-runner#{RbConfig::CONFIG["EXEEXT"]}" == cmd
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
    def self.diagnostic_reports(signame, pid, now)
    end
  end

  def self.gc_stress_to_class?
    unless defined?(@gc_stress_to_class)
      _, _, status = invoke_ruby(["-e""exit GC.respond_to?(:add_stress_to_class)"])
      @gc_stress_to_class = status.success?
    end
    @gc_stress_to_class
  end
end

if defined?(RbConfig)
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
