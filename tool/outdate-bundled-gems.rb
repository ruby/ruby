#!/usr/bin/ruby
require 'fileutils'
require 'rubygems'

fu = FileUtils::Verbose
until ARGV.empty?
  case ARGV.first
  when '--'
    ARGV.shift
    break
  when '-n', '--dryrun'
    fu = FileUtils::DryRun
  when /\A--make=/
    # just to run when `make -n`
  when /\A--mflags=(.*)/
    fu = FileUtils::DryRun if /\A-\S*n/ =~ $1
  when /\A--gem[-_]platform=(.*)/im
    gem_platform = $1
    ruby_platform = nil
  when /\A--ruby[-_]platform=(.*)/im
    ruby_platform = $1
    gem_platform = nil
  when /\A--ruby[-_]version=(.*)/im
    ruby_version = $1
  when /\A-/
    raise "#{$0}: unknown option: #{ARGV.first}"
  else
    break
  end
  ARGV.shift
end

gem_platform ||= (ruby_platform ? Gem::Platform.new(ruby_platform) : Gem::Platform.local).to_s
ruby_version ||= RbConfig::CONFIG['ruby_version'] # This may not have "-static"

class Removal
  attr_reader :base

  def initialize(base = nil)
    @base = (File.join(base, "/") if base)
    @remove = {}
  end

  def prefixed(name)
    @base ? File.join(@base, name) : name
  end

  def stripped(name)
    if @base && name.start_with?(@base)
      name[@base.size..-1]
    else
      name
    end
  end

  def slash(name)
    name.sub(%r[[^/]\K\z], '/')
  end

  def exist?(name)
    !@remove.fetch(name) {|k| @remove[k] = !File.exist?(prefixed(name))}
  end
  def directory?(name)
    !@remove.fetch(slash(name)) {|k| @remove[k] = !File.directory?(prefixed(name))}
  end

  def unlink(name)
    @remove[stripped(name)] = :rm_f
  end
  def rmdir(name)
    @remove[slash(stripped(name))] = :rm_rf
  end

  def glob(pattern, *rest)
    Dir.glob(prefixed(pattern), *rest) {|n|
      yield stripped(n)
    }
  end

  def each_file
    @remove.each {|k, v| yield prefixed(k) if v == :rm_f}
  end

  def each_directory
    @remove.each {|k, v| yield prefixed(k) if v == :rm_rf}
  end
end

srcdir = Removal.new(ARGV.shift)
curdir = !srcdir.base || File.identical?(srcdir.base, ".") ? srcdir : Removal.new

srcdir.glob(".bundle/gems/*/") do |dir|
  unless srcdir.exist?("gems/#{File.basename(dir)}.gem")
    srcdir.rmdir(dir)
  end
end

srcdir.glob(".bundle/specifications/*.gemspec") do |spec|
  unless srcdir.directory?(".bundle/gems/#{File.basename(spec, '.gemspec')}/")
    srcdir.unlink(spec)
  end
end

curdir.glob(".bundle/specifications/*.gemspec") do |spec|
  unless srcdir.directory?(".bundle/gems/#{File.basename(spec, '.gemspec')}")
    curdir.unlink(spec)
  end
end

curdir.glob(".bundle/gems/*/") do |dir|
  base = File.basename(dir)
  unless curdir.exist?(".bundle/specifications/#{base}.gemspec") or
        curdir.exist?("#{dir}/.bundled.#{base}.gemspec")
    curdir.rmdir(dir)
  end
end

curdir.glob(".bundle/{extensions,.timestamp}/*/") do |dir|
  unless File.fnmatch?(gem_platform, File.basename(dir))
    curdir.rmdir(dir)
  end
end

curdir.glob(".bundle/{extensions,.timestamp}/#{gem_platform}/*/") do |dir|
  unless File.fnmatch?(ruby_version, File.basename(dir, '-static'))
    curdir.rmdir(dir)
  end
end

curdir.glob(".bundle/extensions/#{gem_platform}/#{ruby_version}/*/") do |dir|
  unless curdir.exist?(".bundle/specifications/#{File.basename(dir)}.gemspec")
    curdir.rmdir(dir)
  end
end

curdir.glob(".bundle/.timestamp/#{gem_platform}/#{ruby_version}/.*.time") do |stamp|
  dir = stamp[%r[/\.([^/]+)\.time\z], 1].gsub('.-.', '/')[%r[\A[^/]+/[^/]+]]
  unless curdir.directory?(File.join(".bundle", dir))
    curdir.unlink(stamp)
  end
end

srcdir.each_file {|f| fu.rm_f(f)}
srcdir.each_directory {|d| fu.rm_rf(d)}
unless curdir.equal?(srcdir)
  curdir.each_file {|f| fu.rm_f(f)}
  curdir.each_directory {|d| fu.rm_rf(d)}
end
