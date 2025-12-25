class Module
  # Internal helper for built-in initializations to define methods only when JIT is enabled.
  # This method is removed in jit_undef.rb.
  private def with_jit(&block) # :nodoc:
    # ZJIT currently doesn't compile Array#each properly, so it's disabled for now.
    if defined?(RubyVM::ZJIT) && false # TODO: remove `&& false` (Shopify/ruby#667)
      RubyVM::ZJIT.send(:add_jit_hook, block)
    elsif defined?(RubyVM::YJIT)
      RubyVM::YJIT.send(:add_jit_hook, block)
    end
  end
end
