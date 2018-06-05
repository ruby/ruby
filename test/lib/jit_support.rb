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
      _, err = JITSupport.eval_with_jit('proc {}.call', verbose: 1, min_calls: 1, timeout: 10)
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
  def eval_with_jit(env = nil, script, verbose: 0, min_calls: 5, save_temps: false, timeout: JIT_TIMEOUT)
    args = ['--disable-gems', '--jit-wait', "--jit-verbose=#{verbose}", "--jit-min-calls=#{min_calls}"]
    args << '--jit-save-temps' if save_temps
    args << '-e' << script
    args.unshift(env) if env
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
end
