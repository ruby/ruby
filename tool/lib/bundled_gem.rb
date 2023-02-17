require 'fileutils'
require 'rubygems'
require 'rubygems/package'

# This library is used by "make extract-gems" to
# unpack bundled gem files.

module BundledGem
  module_function

  def unpack(file, *rest)
    pkg = Gem::Package.new(file)
    prepare_test(pkg.spec, *rest) {|dir| pkg.extract_files(dir)}
    puts "Unpacked #{file}"
  end

  def build(gemspec, version, outdir = ".", validation: true)
    outdir = File.expand_path(outdir)
    gemdir, gemfile = File.split(gemspec)
    Dir.chdir(gemdir) do
      if gemspec == "gems/src/minitest/minitest.gemspec" && !File.exist?("minitest.gemspec")
        # The repository of minitest does not include minitest.gemspec because it uses hoe.
        # This creates a dummy gemspec.
        File.write("minitest.gemspec", <<END)
Gem::Specification.new do |s|
  s.name = "minitest"
  s.version = #{ File.read("lib/minitest.rb")[/VERSION = "(.+?)"/, 1].dump }

  s.require_paths = ["lib"]
  s.authors = ["Ryan Davis"]
  s.date = "#{ Time.now.strftime("%Y-%m-%d") }"
  s.description = "(dummy gemspec)"
  s.email = ["ryand-ruby@zenspider.com"]
  s.extra_rdoc_files = ["History.rdoc", "Manifest.txt", "README.rdoc"]
  s.files = [#{ Dir.glob("**/*").reject {|s| File.directory?(s) }.map {|s| s.dump }.join(",") }]
  s.homepage = "https://github.com/seattlerb/minitest"
  s.licenses = ["MIT"]
  s.rdoc_options = ["--main", "README.rdoc"]
  s.summary = "(dummy gemspec)"

  s.add_development_dependency(%q<rdoc>, [">= 4.0", "< 7"])
  s.add_development_dependency(%q<hoe>, ["~> 4.0"])
end
END
      end
      spec = Gem::Specification.load(gemfile)
      abort "Failed to load #{gemspec}" unless spec
      abort "Unexpected version #{spec.version}" unless spec.version == Gem::Version.new(version)
      output = File.join(outdir, spec.file_name)
      FileUtils.rm_rf(output)
      Gem::Package.build(spec, validation == false, validation, output)
    end
  end

  def copy(path, *rest)
    path, n = File.split(path)
    spec = Dir.chdir(path) {Gem::Specification.load(n)} or raise "Cannot load #{path}"
    prepare_test(spec, *rest) do |dir|
      FileUtils.rm_rf(dir)
      files = spec.files.reject {|f| f.start_with?(".git")}
      dirs = files.map {|f| File.dirname(f) if f.include?("/")}.uniq
      FileUtils.mkdir_p(dirs.map {|d| d ? "#{dir}/#{d}" : dir}.sort_by {|d| d.count("/")})
      files.each do |f|
        File.copy_stream(File.join(path, f), File.join(dir, f))
      end
    end
    puts "Copied #{path}"
  end

  def prepare_test(spec, dir = ".")
    target = spec.full_name
    Gem.ensure_gem_subdirectories(dir)
    gem_dir = File.join(dir, "gems", target)
    yield gem_dir
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
  end
end
