#!/usr/bin/env ruby
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

at_exit { $SAFE = 1 }

require 'fileutils'
require 'test/unit'
require 'tmpdir'
require 'uri'
require 'rubygems/gem_open_uri'
require 'rubygems/source_info_cache'

require File.join(File.expand_path(File.dirname(__FILE__)), 'mockgemui')

module Gem
  def self.source_index=(si)
    @@source_index = si
  end

  def self.win_platform=(val)
    @@win_platform = val
  end
end

class FakeFetcher

  attr_reader :data
  attr_accessor :uri
  attr_accessor :paths

  def initialize
    @data = {}
    @paths = []
    @uri = nil
  end

  def fetch_path(path)
    path = path.to_s
    @paths << path
    raise ArgumentError, 'need full URI' unless path =~ %r'^http://'
    data = @data[path]
    raise Gem::RemoteFetcher::FetchError, "no data for #{path}" if data.nil?
    data.respond_to?(:call) ? data.call : data
  end

  def fetch_size(path)
    path = path.to_s
    @paths << path
    raise ArgumentError, 'need full URI' unless path =~ %r'^http://'
    data = @data[path]
    raise Gem::RemoteFetcher::FetchError, "no data for #{path}" if data.nil?
    data.respond_to?(:call) ? data.call : data.length
  end

end

class RubyGemTestCase < Test::Unit::TestCase

  include Gem::DefaultUserInteraction

  undef_method :default_test if instance_methods.include? 'default_test' or
                                instance_methods.include? :default_test

  def setup
    super

    @ui = MockGemUi.new
    tmpdir = nil
    Dir.chdir Dir.tmpdir do tmpdir = Dir.pwd end # HACK OSX /private/tmp
    @tempdir = File.join tmpdir, "test_rubygems_#{$$}"
    @tempdir.untaint
    @gemhome = File.join @tempdir, "gemhome"
    @gemcache = File.join(@gemhome, "source_cache")
    @usrcache = File.join(@gemhome, ".gem", "user_cache")

    FileUtils.mkdir_p @gemhome

    ENV['GEMCACHE'] = @usrcache
    Gem.use_paths(@gemhome)
    Gem.loaded_specs.clear

    Gem.configuration.verbose = true
    Gem.configuration.update_sources = true

    @gem_repo = "http://gems.example.com"
    Gem.sources.replace [@gem_repo]

    @orig_BASERUBY = Gem::ConfigMap[:BASERUBY]
    Gem::ConfigMap[:BASERUBY] = Gem::ConfigMap[:RUBY_INSTALL_NAME]

    @orig_arch = Gem::ConfigMap[:arch]

    if win_platform?
      util_set_arch 'i386-mswin32'
    else
      util_set_arch 'i686-darwin8.10.1'
    end

    @marshal_version = "#{Marshal::MAJOR_VERSION}.#{Marshal::MINOR_VERSION}"
  end

  def teardown
    Gem::ConfigMap[:BASERUBY] = @orig_BASERUBY
    Gem::ConfigMap[:arch] = @orig_arch

    if defined? Gem::RemoteFetcher then
      Gem::RemoteFetcher.instance_variable_set :@fetcher, nil
    end

    FileUtils.rm_rf @tempdir

    ENV.delete 'GEMCACHE'
    ENV.delete 'GEM_HOME'
    ENV.delete 'GEM_PATH'

    Gem.clear_paths
    Gem::SourceInfoCache.instance_variable_set :@cache, nil
  end

  def install_gem gem
    require 'rubygems/installer'

    use_ui MockGemUi.new do
      Dir.chdir @tempdir do
        Gem::Builder.new(gem).build
      end
    end

    gem = File.join(@tempdir, "#{gem.full_name}.gem").untaint
    Gem::Installer.new(gem).install
  end

  def prep_cache_files(lc)
    [ [lc.system_cache_file, 'sys'],
      [lc.user_cache_file, 'usr'],
    ].each do |fn, data|
      FileUtils.mkdir_p File.dirname(fn).untaint
      open(fn.dup.untaint, "wb") { |f| f.write(Marshal.dump({'key' => data})) }
    end
  end

  def read_cache(fn)
    open(fn.dup.untaint) { |f| Marshal.load f.read }
  end

  def write_file(path)
    path = File.join(@gemhome, path)
    dir = File.dirname path
    FileUtils.mkdir_p dir
    File.open(path, "w") { |io|
      yield(io)
    }
    path
  end

  def quick_gem(gemname, version='2')
    require 'rubygems/specification'

    spec = Gem::Specification.new do |s|
      s.platform = Gem::Platform::RUBY
      s.name = gemname
      s.version = version
      s.author = 'A User'
      s.email = 'example@example.com'
      s.homepage = 'http://example.com'
      s.has_rdoc = true
      s.summary = "this is a summary"
      s.description = "This is a test description"

      yield(s) if block_given?
    end

    path = File.join "specifications", "#{spec.full_name}.gemspec"
    written_path = write_file path do |io|
      io.write(spec.to_ruby)
    end

    spec.loaded_from = written_path

    return spec
  end

  def util_build_gem(spec)
    dir = File.join(@gemhome, 'gems', spec.full_name)
    FileUtils.mkdir_p dir

    Dir.chdir dir do
      spec.files.each do |file|
        next if File.exist? file
        FileUtils.mkdir_p File.dirname(file)
        File.open file, 'w' do |fp| fp.puts "# #{file}" end
      end

      use_ui MockGemUi.new do
        Gem::Builder.new(spec).build
      end

      FileUtils.mv "#{spec.full_name}.gem",
                   File.join(@gemhome, 'cache', "#{spec.original_name}.gem")
    end
  end

  def util_make_gems
    spec = proc do |s|
      s.files = %w[lib/code.rb]
      s.require_paths = %w[lib]
    end

    @a1 = quick_gem('a', '1', &spec)
    @a2 = quick_gem('a', '2', &spec)
    @b2 = quick_gem('b', '2', &spec)
    @c1_2   = quick_gem('c', '1.2',   &spec)
    @pl1     = quick_gem 'pl', '1' do |s| # l for legacy
      s.files = %w[lib/code.rb]
      s.require_paths = %w[lib]
      s.platform = Gem::Platform.new 'i386-linux'
      s.instance_variable_set :@original_platform, 'i386-linux'
    end

    write_file File.join(*%W[gems #{@a1.original_name} lib code.rb]) do end
    write_file File.join(*%W[gems #{@a2.original_name} lib code.rb]) do end
    write_file File.join(*%W[gems #{@b2.original_name} lib code.rb]) do end
    write_file File.join(*%W[gems #{@c1_2.original_name} lib code.rb]) do end
    write_file File.join(*%W[gems #{@pl1.original_name} lib code.rb]) do end

    [@a1, @a2, @b2, @c1_2, @pl1].each { |spec| util_build_gem spec }

    FileUtils.rm_r File.join(@gemhome, 'gems', @pl1.original_name)

    Gem.source_index = nil
  end

  ##
  # Set the platform to +cpu+ and +os+

  def util_set_arch(arch)
    Gem::ConfigMap[:arch] = arch
    platform = Gem::Platform.new arch

    Gem.instance_variable_set :@platforms, nil
    Gem::Platform.instance_variable_set :@local, nil

    platform
  end

  def util_setup_fake_fetcher
    require 'zlib'
    require 'socket'
    require 'rubygems/remote_fetcher'

    @uri = URI.parse @gem_repo
    @fetcher = FakeFetcher.new
    @fetcher.uri = @uri

    @gem1 = quick_gem 'gem_one' do |gem|
      gem.files = %w[Rakefile lib/gem_one.rb]
    end

    @gem2 = quick_gem 'gem_two' do |gem|
      gem.files = %w[Rakefile lib/gem_two.rb]
    end

    @gem3 = quick_gem 'gem_three' do |gem| # missing gem
      gem.files = %w[Rakefile lib/gem_three.rb]
    end

    # this gem has a higher version and longer name than the gem we want
    @gem4 = quick_gem 'gem_one_evil', '666' do |gem|
      gem.files = %w[Rakefile lib/gem_one.rb]
    end

    @all_gems = [@gem1, @gem2, @gem3, @gem4].sort
    @all_gem_names = @all_gems.map { |gem| gem.full_name }

    gem_names = [@gem1.full_name, @gem2.full_name, @gem4.full_name]
    @gem_names = gem_names.sort.join("\n")

    @source_index = Gem::SourceIndex.new @gem1.full_name => @gem1,
                                         @gem2.full_name => @gem2,
                                         @gem4.full_name => @gem4

    Gem::RemoteFetcher.instance_variable_set :@fetcher, @fetcher
  end

  def util_setup_source_info_cache(*specs)
    require 'rubygems/source_info_cache_entry'

    specs = Hash[*specs.map { |spec| [spec.full_name, spec] }.flatten]
    si = Gem::SourceIndex.new specs

    sice = Gem::SourceInfoCacheEntry.new si, 0
    sic = Gem::SourceInfoCache.new
    sic.set_cache_data( { @gem_repo => sice } )
    Gem::SourceInfoCache.instance_variable_set :@cache, sic
    si
  end

  def util_zip(data)
    Zlib::Deflate.deflate data
  end

  def self.win_platform?
    Gem.win_platform?
  end

  def win_platform?
    Gem.win_platform?
  end

end

