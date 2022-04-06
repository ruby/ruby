require 'fileutils'
require 'rubygems'
require 'rubygems/package'

# This library is used by "make extract-gems" to
# unpack bundled gem files.

def Gem.unpack(file, dir = nil, spec_dir = nil)
  pkg = Gem::Package.new(file)
  spec = pkg.spec
  target = spec.full_name
  target = File.join(dir, target) if dir
  pkg.extract_files target
  FileUtils.mkdir_p(spec_dir ||= target)
  spec_file = File.join(spec_dir, "#{spec.name}-#{spec.version}.gemspec")
  open(spec_file, 'wb') do |f|
    f.print spec.to_ruby
  end
  puts "Unpacked #{file}"
end
