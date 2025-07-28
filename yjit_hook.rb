# Remove the helper defined in kernel.rb
class Module
  undef :with_yjit
end
