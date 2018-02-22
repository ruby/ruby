module JITSupport
  JIT_TIMEOUT = 600 # 10min for each...
  JIT_SUCCESS_PREFIX = 'JIT success \(\d+\.\dms\)'
  SUPPORTED_COMPILERS = [
    'gcc',
    'clang',
  ]

  module_function
  def eval_with_jit(script, verbose: 0, min_calls: 5, timeout: JIT_TIMEOUT)
    EnvUtil.invoke_ruby(
      ['--disable-gems', '--jit-wait', "--jit-verbose=#{verbose}", "--jit-min-calls=#{min_calls}", '-e', script],
      '', true, true, timeout: timeout,
    )
  end

  def supported?
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
      err.match?(JIT_SUCCESS_PREFIX)
    end
  end
end
