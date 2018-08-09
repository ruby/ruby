module JITSupport
  JIT_TIMEOUT = 600 # 10min for each...
  JIT_SUCCESS_PREFIX = 'JIT success \(\d+\.\dms\)'
  SUPPORTED_COMPILERS = [
    'gcc',
    'clang',
  ]

  def self.check_support
    # Experimental. If you want to ensure JIT is working with this test, please set this for now.
    if ENV.key?('RUBY_FORCE_TEST_JIT')
      return true
    end

    # Very pessimistic check. With this check, we can't ensure JIT is working.
    begin
      _, err = JITSupport.eval_with_jit_without_retry('proc {}.call', verbose: 1, min_calls: 1, timeout: 10)
    rescue Timeout::Error
      $stderr.puts "TestJIT: #jit_supported? check timed out"
      false
    else
      err.match?(JIT_SUCCESS_PREFIX).tap do |success|
        unless success
          $stderr.puts "TestJIT.check_support stderr:\n```\n#{err}\n```\n"
        end
      end
    end
  end

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
    args << '-e' << script
    base_env = { 'MJIT_SEARCH_BUILD_DIR' => 'true' } # workaround to skip requiring `make install` for `make test-all`
    args.unshift(env ? base_env.merge!(env) : base_env)
    EnvUtil.invoke_ruby(args,
      '', true, true, timeout: timeout,
    )
  end

  def supported?
    return @supported if defined?(@supported)
    @supported = JITSupport.check_support.tap do |supported|
      unless supported
        warn "JIT tests are skipped since JIT seems not working. Set RUBY_FORCE_TEST_JIT=1 to let it fail.", uplevel: 1
      end
    end
  end

  def remove_mjit_logs(stderr)
    if RubyVM::MJIT.enabled?
      stderr.gsub(/^MJIT warning: Skipped to compile unsupported instruction: \w+\n/m, '')
    else
      stderr
    end
  end

  def code_block(code)
    "```\n#{code}\n```\n\n"
  end

  # We're retrying cc1 not found error on gcc, which should be solved in the future but ignored for now.
  def retried_stderr?(stderr)
    RbConfig::CONFIG['CC'].start_with?('gcc') &&
      stderr.include?("error trying to exec 'cc1': execvp: No such file or directory")
  end
end
