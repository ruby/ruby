require 'rubygems'
require 'rubygems/package'

def Gem.unpack(file, dir = nil)
  pkg = Gem::Package.new(file)
  spec = pkg.spec
  target = spec.full_name
  target = File.join(dir, target) if dir
  pkg.extract_files target
  spec_file = File.join(target, "#{spec.name}.gemspec")
  open(spec_file, 'wb') do |f|
    f.print spec.to_ruby
  end
  puts "Unpacked #{file}"
end
