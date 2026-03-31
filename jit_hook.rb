class Module
  # Internal helper for built-in initializations to define methods only when JIT is enabled.
  # This method is removed in jit_undef.rb.
  private def with_jit(&block) # :nodoc:
    if defined?(RubyVM::ZJIT)
      RubyVM::ZJIT.send(:add_jit_hook, block)
    end
    if defined?(RubyVM::YJIT)
      RubyVM::YJIT.send(:add_jit_hook, block)
    end
  end
end
