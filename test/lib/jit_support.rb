require 'rbconfig'

module JITSupport
  JIT_TIMEOUT = 600 # 10min for each...
  JIT_SUCCESS_PREFIX = 'JIT success \(\d+\.\dms\)'
  JIT_COMPACTION_PREFIX = 'JIT compaction \(\d+\.\dms\)'
  UNSUPPORTED_COMPILERS = [
    %r[\A/opt/intel/.*/bin/intel64/icc\b],
    %r[\A/opt/developerstudio\d+\.\d+/bin/cc\z],
  ]
  # freebsd12: cc1 internal failure https://rubyci.org/logs/rubyci.s3.amazonaws.com/freebsd12/ruby-master/log/20200306T103003Z.fail.html.gz
  # rhel8: one or more PCH files were found, but they were invalid https://rubyci.org/logs/rubyci.s3.amazonaws.com/rhel8/ruby-master/log/20200306T153003Z.fail.html.gz
  # centos8: ditto https://rubyci.org/logs/rubyci.s3.amazonaws.com/centos8/ruby-master/log/20200512T003004Z.fail.html.gz
  PENDING_RUBYCI_NICKNAMES = %w[
    freebsd12
    rhel8
    centos8
  ]

  module_function
  # Run Ruby script with --jit-wait (Synchronous JIT compilation).
  # Returns [stdout, stderr]
  def eval_with_jit(env = nil, script, **opts)
    stdout, stderr = nil, nil
    # retry 3 times while cc1 error happens.
    3.times do |i|
      stdout, stderr, status = eval_with_jit_without_retry(env, script, **opts)
      assert_equal(true, status.success?, "Failed to run script with JIT:\n#{code_block(script)}\nstdout:\n#{code_block(stdout)}\nstderr:\n#{code_block(stderr)}")
      break unless retried_stderr?(stderr)
    end
    [stdout, stderr]
  end

  def eval_with_jit_without_retry(env = nil, script, verbose: 0, min_calls: 5, save_temps: false, max_cache: 1000, wait: true, timeout: JIT_TIMEOUT)
    args = [
      '--disable-gems', "--jit-verbose=#{verbose}",
      "--jit-min-calls=#{min_calls}", "--jit-max-cache=#{max_cache}",
    ]
    args << '--jit-wait' if wait
    args << '--jit-save-temps' if save_temps
    args << '--jit-debug' if defined?(@jit_debug) && @jit_debug
    args << '-e' << script
    base_env = { 'MJIT_SEARCH_BUILD_DIR' => 'true' } # workaround to skip requiring `make install` for `make test-all`
    if preloadenv = RbConfig::CONFIG['PRELOADENV'] and !preloadenv.empty?
      so = "mjit_build_dir.#{RbConfig::CONFIG['SOEXT']}"
      base_env[preloadenv] = File.realpath(so) rescue nil
    end
    args.unshift(env ? base_env.merge!(env) : base_env)
    EnvUtil.invoke_ruby(args,
      '', true, true, timeout: timeout,
    )
  end

  def supported?
    return @supported if defined?(@supported)
    @supported = UNSUPPORTED_COMPILERS.all? do |regexp|
      !regexp.match?(RbConfig::CONFIG['MJIT_CC'])
    end && RbConfig::CONFIG["MJIT_SUPPORT"] != 'no' && !PENDING_RUBYCI_NICKNAMES.include?(ENV['RUBYCI_NICKNAME'])
  end

  def remove_mjit_logs(stderr)
    if RubyVM::MJIT.enabled? # utility for -DFORCE_MJIT_ENABLE
      stderr.gsub(/^MJIT warning: Skipped to compile unsupported instruction: \w+\n/m, '')
    else
      stderr
    end
  end

  def code_block(code)
    %Q["""\n#{code}\n"""\n\n]
  end

  # We're retrying cc1 not found error on gcc, which should be solved in the future but ignored for now.
  def retried_stderr?(stderr)
    RbConfig::CONFIG['CC'].start_with?('gcc') &&
      stderr.include?("error trying to exec 'cc1': execvp: No such file or directory")
  end
end
