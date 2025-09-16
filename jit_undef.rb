# Remove the helper defined in jit_hook.rb
class Module
  undef :with_jit
end
