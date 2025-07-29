class Module
  # Internal helper for built-in initializations to define methods only when JIT is enabled.
  # This method is removed in jit_undef.rb.
  private def with_jit(&block) # :nodoc:
    # ZJIT currently doesn't compile Array#each properly, so it's disabled for now.
    if defined?(RubyVM::ZJIT) && Primitive.rb_zjit_option_enabled_p && false # TODO: remove `&& false`
      # We don't support lazily enabling ZJIT yet, so we can call the block right away.
      block.call
    elsif defined?(RubyVM::YJIT)
      RubyVM::YJIT.send(:add_jit_hook, block)
    end
  end
end
