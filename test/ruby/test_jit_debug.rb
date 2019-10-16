require_relative 'test_jit'

return unless defined?(TestJIT)
return if RbConfig::CONFIG['CPPFLAGS'].include?('-DVM_CHECK_MODE')

class TestJITDebug < TestJIT
  def setup
    # let `#eval_with_jit` use --jit-debug
    @jit_debug = true
  end
end
