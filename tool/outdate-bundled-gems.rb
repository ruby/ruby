#!/usr/bin/ruby
require 'fileutils'
require 'rubygems'

fu = FileUtils::Verbose

until ARGV.empty?
  case ARGV.first
  when '--'
    ARGV.shift
    break
  when '-n', '--dry-run', '--dryrun'
    ## -n, --dry-run  Don't remove
    fu = FileUtils::DryRun
  when /\A--make=/
    # just to run when `make -n`
  when /\A--mflags=(.*)/
    fu = FileUtils::DryRun if /\A-\S*n/ =~ $1
  when /\A--gem[-_]platform=(.*)/im
    ## --gem-platform=PLATFORM  Platform in RubyGems style
    gem_platform = $1
    ruby_platform = nil
  when /\A--ruby[-_]platform=(.*)/im
    ## --ruby-platform=PLATFORM  Platform in Ruby style
    ruby_platform = $1
    gem_platform = nil
  when /\A--ruby[-_]version=(.*)/im
    ## --ruby-version=VERSION  Ruby version to keep
    ruby_version = $1
  when /\A--only=(?:(curdir|srcdir)|all)\z/im
    ## --only=(curdir|srcdir|all)  Specify directory to remove gems from
    only = $1&.downcase
  when /\A--all\z/im
    ## --all  Remove all gems not only bundled gems
    all = true
  when /\A--help\z/im
    ## --help  Print this message
    puts "Usage: #$0 [options] [srcdir]"
    File.foreach(__FILE__) do |line|
      line.sub!(/^ *## /, "") or next
      break if line.chomp!.empty?
      opt, desc = line.split(/ {2,}/, 2)
      printf "  %-28s  %s\n", opt, desc
    end
    exit
  when /\A-/
    raise "#{$0}: unknown option: #{ARGV.first}"
  else
    break
  end
  ##
  ARGV.shift
end

gem_platform ||= Gem::Platform.new(ruby_platform).to_s if ruby_platform

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

  def sorted
    @remove.sort_by {|k, | [-k.count("/"), k]}
  end

  def each_file
    sorted.each {|k, v| yield prefixed(k) if v == :rm_f}
  end

  def each_directory
    sorted.each {|k, v| yield prefixed(k) if v == :rm_rf}
  end
end

srcdir = Removal.new(ARGV.shift)
curdir = !srcdir.base || File.identical?(srcdir.base, ".") ? srcdir : Removal.new

bundled = File.readlines("#{srcdir.base}gems/bundled_gems").
            grep(/^(\w[^\#\s]+)\s+[^\#\s]+(?:\s+[^\#\s]+\s+([^\#\s]+))?/) {$~.captures}.to_h rescue nil

srcdir.glob(".bundle/gems/*/") do |dir|
  base = File.basename(dir)
  next if !all && bundled && !bundled.key?(base[/\A.+(?=-)/])
  unless srcdir.exist?("gems/#{base}.gem")
    srcdir.rmdir(dir)
  end
end

srcdir.glob(".bundle/.timestamp/*.revision") do |file|
  unless bundled&.fetch(File.basename(file, ".revision"), nil)
    srcdir.unlink(file)
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
  unless gem_platform and File.fnmatch?(gem_platform, File.basename(dir))
    curdir.rmdir(dir)
  end
end

if gem_platform
  curdir.glob(".bundle/{extensions,.timestamp}/#{gem_platform}/*/") do |dir|
    unless ruby_version and File.fnmatch?(ruby_version, File.basename(dir, '-static'))
      curdir.rmdir(dir)
    end
  end
end

if ruby_version
  curdir.glob(".bundle/extensions/#{gem_platform || '*'}/#{ruby_version}/*/") do |dir|
    unless curdir.exist?(".bundle/specifications/#{File.basename(dir)}.gemspec")
      curdir.rmdir(dir)
    end
  end

  curdir.glob(".bundle/.timestamp/#{gem_platform || '*'}/#{ruby_version}/.*.time") do |stamp|
    dir = stamp[%r[/\.([^/]+)\.time\z], 1].gsub('.-.', '/')[%r[\A[^/]+/[^/]+]]
    unless curdir.directory?(File.join(".bundle", dir))
      curdir.unlink(stamp)
    end
  end
end

unless only == "curdir"
  srcdir.each_file {|f| fu.rm_f(f)}
  srcdir.each_directory {|d| fu.rm_rf(d)}
end
unless only == "srcdir" or curdir.equal?(srcdir)
  curdir.each_file {|f| fu.rm_f(f)}
  curdir.each_directory {|d| fu.rm_rf(d)}
end
