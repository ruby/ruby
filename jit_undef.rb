# Remove the helper defined in jit_hook.rb
class Module
  undef :with_jit
  undef :with_yjit
  undef :with_zjit
end
