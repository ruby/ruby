class Module
  # Internal helper for built-in initializations to define methods only when JIT is enabled.
  # These methods are removed in jit_undef.rb.
  private def with_jit(&block) # :nodoc:
    with_yjit(&block)
    with_zjit(&block)
  end

  private def with_yjit(&block) # :nodoc:
    if defined?(RubyVM::YJIT)
      RubyVM::YJIT.send(:add_jit_hook, block)
    end
  end

  private def with_zjit(&block) # :nodoc:
    if defined?(RubyVM::ZJIT)
      RubyVM::ZJIT.send(:add_jit_hook, block)
    end
  end
end
