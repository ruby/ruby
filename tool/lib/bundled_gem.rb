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
    "forwardable", # prime, rinda
    "ruby2_keywords", # drb
    "strscan" # rexml
  ]

  module_function

  def unpack(file, *rest)
    pkg = Gem::Package.new(file)
    prepare_test(pkg.spec, *rest) {|dir| pkg.extract_files(dir)}
    puts "Unpacked #{file}"
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
end
