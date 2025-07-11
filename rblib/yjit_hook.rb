# If YJIT is enabled, load the YJIT-only version of builtin methods
if defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
  RubyVM::YJIT.send(:call_yjit_hooks)
end

# Remove the helper defined in kernel.rb
class Module
  undef :with_yjit
end
