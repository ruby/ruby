require 'fileutils'
require 'rubygems'
require 'rubygems/package'

# This library is used by "make extract-gems" to
# unpack bundled gem files.

def Gem.unpack(file, dir = ".")
  pkg = Gem::Package.new(file)
  spec = pkg.spec
  target = spec.full_name
  Gem.ensure_gem_subdirectories(dir)
  gem_dir = File.join(dir, "gems", target)
  pkg.extract_files gem_dir
  spec_dir = spec.extensions.empty? ? "specifications" : File.join("gems", target)
  File.binwrite(File.join(dir, spec_dir, "#{target}.gemspec"), spec.to_ruby)
  unless spec.extensions.empty?
    spec.dependencies.clear
    File.binwrite(File.join(dir, spec_dir, ".bundled.#{target}.gemspec"), spec.to_ruby)
  end
  if spec.bindir and spec.executables
    bindir = File.join(dir, "bin")
    Dir.mkdir(bindir) rescue nil
    spec.executables.each do |exe|
      File.open(File.join(bindir, exe), "wb", 0o777) {|f|
        f.print "#!ruby\n",
                %[load File.realpath("../gems/#{target}/#{spec.bindir}/#{exe}", __dir__)\n]
      }
    end
  end
  FileUtils.rm_rf(Dir.glob("#{gem_dir}/.git*"))

  puts "Unpacked #{file}"
end
