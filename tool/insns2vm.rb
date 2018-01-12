#!ruby

# This is used by Makefile.in to generate .inc files.
# See Makefile.in for details.

require_relative 'ruby_vm/scripts/insns2vm'

if $0 == __FILE__
  router(ARGV).each do |(path, generator)|
    str = generator.generate path
    path.write str, mode: 'wb:utf-8'
  end
end
