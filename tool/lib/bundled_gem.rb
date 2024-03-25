require 'fileutils'
require 'rubygems'
require 'rubygems/package'

# This library is used by "make extract-gems" to
# unpack bundled gem files.

module BundledGem
  DEFAULT_GEMS_DEPENDENCIES = [
    "net-protocol", # net-ftp
    "time", # net-ftp
    "singleton", # prime
    "ipaddr", # rinda
    "forwardable" # prime, rinda
  ]

  module_function

  def unpack(file, *rest)
    pkg = Gem::Package.new(file)
    prepare_test(pkg.spec, *rest) {|dir| pkg.extract_files(dir)}
    puts "Unpacked #{file}"
  rescue Gem::Package::FormatError, Errno::ENOENT
    puts "Try with hash version of bundled gems instead of #{file}. We don't use this gem with release version of Ruby."
    if file =~ /^gems\/(\w+)-/
      file = Dir.glob("gems/#{$1}-*.gem").first
    end
    retry
  end

  def build(gemspec, version, outdir = ".", validation: true)
    outdir = File.expand_path(outdir)
    gemdir, gemfile = File.split(gemspec)
    Dir.chdir(gemdir) do
      spec = Gem::Specification.load(gemfile)
      abort "Failed to load #{gemspec}" unless spec
      output = File.join(outdir, spec.file_name)
      FileUtils.rm_rf(output)
      package = Gem::Package.new(output)
      package.spec = spec
      package.build(validation == false)
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
    if spec.extensions.empty?
      spec.dependencies.reject! {|dep| DEFAULT_GEMS_DEPENDENCIES.include?(dep.name)}
    end
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

  def dummy_gemspec(gemspec)
    return if File.exist?(gemspec)
    gemdir, gemfile = File.split(gemspec)
    Dir.chdir(gemdir) do
      spec = Gem::Specification.new do |s|
        s.name = gemfile.chomp(".gemspec")
        s.version = File.read("lib/#{s.name}.rb")[/VERSION = "(.+?)"/, 1]
        s.authors = ["DUMMY"]
        s.email = ["dummy@ruby-lang.org"]
        s.files = Dir.glob("{lib,ext}/**/*").select {|f| File.file?(f)}
        s.licenses = ["Ruby"]
        s.description = "DO NOT USE; dummy gemspec only for test"
        s.summary = "(dummy gemspec)"
      end
      File.write(gemfile, spec.to_ruby)
    end
  end

  def checkout(gemdir, repo, rev, git: $git)
    return unless rev or !git or git.empty?
    unless File.exist?("#{gemdir}/.git")
      puts "Cloning #{repo}"
      command = "#{git} clone #{repo} #{gemdir}"
      system(command) or raise "failed: #{command}"
    end
    puts "Update #{File.basename(gemdir)} to #{rev}"
    command = "#{git} fetch origin #{rev}"
    system(command, chdir: gemdir) or raise "failed: #{command}"
    command = "#{git} checkout --detach #{rev}"
    system(command, chdir: gemdir) or raise "failed: #{command}"
  end
end
