require 'rbconfig'

module JITSupport
  JIT_TIMEOUT = 600 # 10min for each...
  JIT_SUCCESS_PREFIX = 'JIT success \(\d+\.\dms\)'
  JIT_RECOMPILE_PREFIX = 'JIT recompile'
  JIT_COMPACTION_PREFIX = 'JIT compaction \(\d+\.\dms\)'
  UNSUPPORTED_COMPILERS = [
    %r[\A.*/bin/intel64/icc\b],
    %r[\A/opt/developerstudio\d+\.\d+/bin/cc\z],
  ]
  # debian-riscv64: "gcc: internal compiler error: Segmentation fault signal terminated program cc1" https://rubyci.org/logs/rubyci.s3.amazonaws.com/debian-riscv64/ruby-master/log/20200420T083601Z.fail.html.gz
  # freebsd12: cc1 internal failure https://rubyci.org/logs/rubyci.s3.amazonaws.com/freebsd12/ruby-master/log/20200306T103003Z.fail.html.gz
  # rhel8: one or more PCH files were found, but they were invalid https://rubyci.org/logs/rubyci.s3.amazonaws.com/rhel8/ruby-master/log/20200306T153003Z.fail.html.gz
  # centos8: ditto https://rubyci.org/logs/rubyci.s3.amazonaws.com/centos8/ruby-master/log/20200512T003004Z.fail.html.gz
  PENDING_RUBYCI_NICKNAMES = %w[
    debian-riscv64
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
    @supported = RbConfig::CONFIG["MJIT_SUPPORT"] != 'no' && UNSUPPORTED_COMPILERS.all? do |regexp|
      !regexp.match?(RbConfig::CONFIG['MJIT_CC'])
    end && !appveyor_pdb_corrupted? && !PENDING_RUBYCI_NICKNAMES.include?(ENV['RUBYCI_NICKNAME'])
  end

  # AppVeyor's Visual Studio 2013 / 2015 are known to spuriously generate broken pch / pdb, like:
  # error C2859: c:\projects\ruby\x64-mswin_120\include\ruby-2.8.0\x64-mswin64_120\rb_mjit_header-2.8.0.pdb
  # is not the pdb file that was used when this precompiled header was created, recreate the precompiled header.
  # https://ci.appveyor.com/project/ruby/ruby/builds/32159878/job/l2p38snw8yxxpp8h
  #
  # Until we figure out why, this allows us to skip testing JIT when it happens.
  def appveyor_pdb_corrupted?
    return false unless ENV.key?('APPVEYOR')
    stdout, _stderr, _status = eval_with_jit_without_retry('proc {}.call', verbose: 2, min_calls: 1)
    stdout.include?('.pdb is not the pdb file that was used when this precompiled header was created, recreate the precompiled header.')
  end

  def remove_mjit_logs(stderr)
    if defined?(RubyVM::MJIT) && RubyVM::MJIT.enabled? # utility for -DFORCE_MJIT_ENABLE
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
