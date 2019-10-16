require_relative 'test_jit'

class TestJITDebug < TestJIT
  def setup
    # let `#eval_with_jit` use --jit-debug
    @jit_debug = true
  end
end
