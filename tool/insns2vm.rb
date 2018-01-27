#!ruby

# This is used by Makefile.in to generate .inc files.
# See Makefile.in for details.

require_relative 'ruby_vm/scripts/insns2vm'

if $0 == __FILE__
  RubyVM::Insns2VM.router(ARGV).each do |(path, generator)|
    str = generator.generate path
    path.open 'wb:utf-8' do |fp|
      fp.write str
    end
  end
end
