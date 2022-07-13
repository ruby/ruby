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
  if spec.extensions.empty?
    spec_dir ||= target
  else
    spec_dir = target
  end
  FileUtils.mkdir_p(spec_dir)
  File.binwrite(File.join(spec_dir, "#{spec.name}-#{spec.version}.gemspec"), spec.to_ruby)
  unless spec.extensions.empty? or spec.dependencies.empty?
    spec.dependencies.clear
  end
  File.binwrite(File.join(spec_dir, ".bundled.#{spec.name}-#{spec.version}.gemspec"), spec.to_ruby)
  puts "Unpacked #{file}"
end
