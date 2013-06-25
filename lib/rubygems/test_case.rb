# TODO: $SAFE = 1

if defined? Gem::QuickLoader
  Gem::QuickLoader.load_full_rubygems_library
else
  require 'rubygems'
end

begin
  gem 'minitest'
rescue Gem::LoadError
end

# We have to load these up front because otherwise we'll try to load
# them while we're testing rubygems, and thus we can't actually load them.
unless Gem::Dependency.new('rdoc', '>= 3.10').matching_specs.empty?
  gem 'rdoc'
  gem 'json'
end

require 'rubygems/deprecate'
require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require 'uri'
require 'rubygems/package'
require 'rubygems/test_utilities'
require 'pp'
require 'zlib'
require 'pathname'
require 'shellwords'
Gem.load_yaml

require 'rubygems/mock_gem_ui'

module Gem

  ##
  # Allows setting the gem path searcher.  This method is available when
  # requiring 'rubygems/test_case'

  def self.searcher=(searcher)
    @searcher = searcher
  end

  ##
  # Allows toggling Windows behavior.  This method is available when requiring
  # 'rubygems/test_case'

  def self.win_platform=(val)
    @@win_platform = val
  end

  ##
  # Allows setting path to ruby.  This method is available when requiring
  # 'rubygems/test_case'

  def self.ruby= ruby
    @ruby = ruby
  end

  ##
  # When rubygems/test_case is required the default user interaction is a
  # MockGemUi.

  module DefaultUserInteraction
    @ui = Gem::MockGemUi.new
  end
end

##
# RubyGemTestCase provides a variety of methods for testing rubygems and
# gem-related behavior in a sandbox.  Through RubyGemTestCase you can install
# and uninstall gems, fetch remote gems through a stub fetcher and be assured
# your normal set of gems is not affected.
#
# Tests are always run at a safe level of 1.

class Gem::TestCase < MiniTest::Unit::TestCase

  # TODO: move to minitest
  def assert_path_exists path, msg = nil
    msg = message(msg) { "Expected path '#{path}' to exist" }
    assert File.exist?(path), msg
  end

  # TODO: move to minitest
  def refute_path_exists path, msg = nil
    msg = message(msg) { "Expected path '#{path}' to not exist" }
    refute File.exist?(path), msg
  end

  def scan_make_command_lines(output)
    output.scan(/^#{Regexp.escape make_command}(?:[[:blank:]].*)?$/)
  end

  def parse_make_command_line(line)
    command, *args = line.shellsplit

    targets = []
    macros = {}

    args.each do |arg|
      case arg
      when /\A(\w+)=/
        macros[$1] = $'
      else
        targets << arg
      end
    end

    targets << '' if targets.empty?

    {
      :command => command,
      :targets => targets,
      :macros => macros,
    }
  end

  def assert_contains_make_command(target, output, msg = nil)
    if output.match(/\n/)
      msg = message(msg) {
        'Expected output containing make command "%s": %s' % [
          ('%s %s' % [make_command, target]).rstrip,
          output.inspect
        ]
      }
    else
      msg = message(msg) {
        'Expected make command "%s": %s' % [
          ('%s %s' % [make_command, target]).rstrip,
          output.inspect
        ]
      }
    end

    assert scan_make_command_lines(output).any? { |line|
      make = parse_make_command_line(line)

      if make[:targets].include?(target)
        yield make, line if block_given?
        true
      else
        false
      end
    }, msg
  end

  include Gem::DefaultUserInteraction

  undef_method :default_test if instance_methods.include? 'default_test' or
                                instance_methods.include? :default_test

  @@project_dir = Dir.pwd.untaint unless defined?(@@project_dir)

  @@initial_reset = false

  ##
  # #setup prepares a sandboxed location to install gems.  All installs are
  # directed to a temporary directory.  All install plugins are removed.
  #
  # If the +RUBY+ environment variable is set the given path is used for
  # Gem::ruby.  The local platform is set to <tt>i386-mswin32</tt> for Windows
  # or <tt>i686-darwin8.10.1</tt> otherwise.
  #
  # If the +KEEP_FILES+ environment variable is set the files will not be
  # removed from <tt>/tmp/test_rubygems_#{$$}.#{Time.now.to_i}</tt>.

  def setup
    super

    @orig_gem_home = ENV['GEM_HOME']
    @orig_gem_path = ENV['GEM_PATH']

    @current_dir = Dir.pwd
    @ui = Gem::MockGemUi.new

    tmpdir = File.expand_path Dir.tmpdir
    tmpdir.untaint

    if ENV['KEEP_FILES'] then
      @tempdir = File.join(tmpdir, "test_rubygems_#{$$}.#{Time.now.to_i}")
    else
      @tempdir = File.join(tmpdir, "test_rubygems_#{$$}")
    end
    @tempdir.untaint

    FileUtils.mkdir_p @tempdir

    # This makes the tempdir consistent on OS X.
    # File.expand_path Dir.tmpdir                      #=> "/var/..."
    # Dir.chdir Dir.tmpdir do File.expand_path '.' end #=> "/private/var/..."
    # TODO use File#realpath above instead of #expand_path once 1.8 support is
    # dropped.
    Dir.chdir @tempdir do
      @tempdir = File.expand_path '.'
      @tempdir.untaint
    end

    @gemhome  = File.join @tempdir, 'gemhome'
    @userhome = File.join @tempdir, 'userhome'

    @orig_ruby = if ENV['RUBY'] then
                   ruby = Gem.instance_variable_get :@ruby
                   Gem.instance_variable_set :@ruby, ENV['RUBY']
                   ruby
                 end

    Gem.ensure_gem_subdirectories @gemhome

    @orig_LOAD_PATH = $LOAD_PATH.dup
    $LOAD_PATH.map! { |s| File.expand_path(s).untaint }

    Dir.chdir @tempdir

    @orig_ENV_HOME = ENV['HOME']
    ENV['HOME'] = @userhome
    Gem.instance_variable_set :@user_home, nil

    FileUtils.mkdir_p @gemhome
    FileUtils.mkdir_p @userhome

    @default_dir = File.join @tempdir, 'default'
    @default_spec_dir = File.join @default_dir, "specifications", "default"
    Gem.instance_variable_set :@default_dir, @default_dir
    FileUtils.mkdir_p @default_spec_dir

    # We use Gem::Specification.reset the first time only so that if there
    # are unresolved deps that leak into the whole test suite, they're at least
    # reported once.
    if @@initial_reset
      Gem::Specification.unresolved_deps.clear # done to avoid cross-test warnings
    else
      @@initial_reset = true
      Gem::Specification.reset
    end
    Gem.use_paths(@gemhome)

    Gem::Security.reset

    Gem.loaded_specs.clear
    Gem.clear_default_specs
    Gem::Specification.unresolved_deps.clear

    Gem.configuration.verbose = true
    Gem.configuration.update_sources = true

    Gem::RemoteFetcher.fetcher = Gem::FakeFetcher.new

    @gem_repo = "http://gems.example.com/"
    @uri = URI.parse @gem_repo
    Gem.sources.replace [@gem_repo]

    Gem.searcher = nil
    Gem::SpecFetcher.fetcher = nil
    @orig_BASERUBY = Gem::ConfigMap[:BASERUBY]
    Gem::ConfigMap[:BASERUBY] = Gem::ConfigMap[:ruby_install_name]

    @orig_arch = Gem::ConfigMap[:arch]

    if win_platform?
      util_set_arch 'i386-mswin32'
    else
      util_set_arch 'i686-darwin8.10.1'
    end

    @marshal_version = "#{Marshal::MAJOR_VERSION}.#{Marshal::MINOR_VERSION}"

    # TODO: move to installer test cases
    Gem.post_build_hooks.clear
    Gem.post_install_hooks.clear
    Gem.done_installing_hooks.clear
    Gem.post_reset_hooks.clear
    Gem.post_uninstall_hooks.clear
    Gem.pre_install_hooks.clear
    Gem.pre_reset_hooks.clear
    Gem.pre_uninstall_hooks.clear

    # TODO: move to installer test cases
    Gem.post_build do |installer|
      @post_build_hook_arg = installer
      true
    end

    Gem.post_install do |installer|
      @post_install_hook_arg = installer
    end

    Gem.post_uninstall do |uninstaller|
      @post_uninstall_hook_arg = uninstaller
    end

    Gem.pre_install do |installer|
      @pre_install_hook_arg = installer
      true
    end

    Gem.pre_uninstall do |uninstaller|
      @pre_uninstall_hook_arg = uninstaller
    end
  end

  ##
  # #teardown restores the process to its original state and removes the
  # tempdir unless the +KEEP_FILES+ environment variable was set.

  def teardown
    $LOAD_PATH.replace @orig_LOAD_PATH if @orig_LOAD_PATH

    Gem::ConfigMap[:BASERUBY] = @orig_BASERUBY
    Gem::ConfigMap[:arch] = @orig_arch

    if defined? Gem::RemoteFetcher then
      Gem::RemoteFetcher.fetcher = nil
    end

    Dir.chdir @current_dir

    FileUtils.rm_rf @tempdir unless ENV['KEEP_FILES']

    ENV['GEM_HOME'] = @orig_gem_home
    ENV['GEM_PATH'] = @orig_gem_path

    _ = @orig_ruby
    Gem.instance_variable_set :@ruby, @orig_ruby if @orig_ruby

    if @orig_ENV_HOME then
      ENV['HOME'] = @orig_ENV_HOME
    else
      ENV.delete 'HOME'
    end

    Gem.instance_variable_set :@default_dir, nil
  end

  ##
  # Builds and installs the Gem::Specification +spec+

  def install_gem spec, options = {}
    require 'rubygems/installer'

    gem = File.join @tempdir, "gems", "#{spec.full_name}.gem"

    unless File.exists? gem
      use_ui Gem::MockGemUi.new do
        Dir.chdir @tempdir do
          Gem::Package.build spec
        end
      end

      gem = File.join(@tempdir, File.basename(spec.cache_file)).untaint
    end

    Gem::Installer.new(gem, options.merge({:wrappers => true})).install
  end

  ##
  # Builds and installs the Gem::Specification +spec+ into the user dir

  def install_gem_user spec
    install_gem spec, :user_install => true
  end

  ##
  # Uninstalls the Gem::Specification +spec+
  def uninstall_gem spec
    require 'rubygems/uninstaller'

    Gem::Uninstaller.new(spec.name,
                         :executables => true, :user_install => true).uninstall
  end

  ##
  # creates a temporary directory with hax
  # TODO: deprecate and remove

  def create_tmpdir
    tmpdir = nil
    Dir.chdir Dir.tmpdir do tmpdir = Dir.pwd end # HACK OSX /private/tmp
    tmpdir = File.join tmpdir, "test_rubygems_#{$$}"
    FileUtils.mkdir_p tmpdir
    return tmpdir
  end

  ##
  # Enables pretty-print for all tests

  def mu_pp(obj)
    s = ''
    s = PP.pp obj, s
    s = s.force_encoding(Encoding.default_external) if defined? Encoding
    s.chomp
  end

  ##
  # Reads a Marshal file at +path+

  def read_cache(path)
    open path.dup.untaint, 'rb' do |io|
      Marshal.load io.read
    end
  end

  ##
  # Reads a binary file at +path+

  def read_binary(path)
    Gem.read_binary path
  end

  ##
  # Writes a binary file to +path+ which is relative to +@gemhome+

  def write_file(path)
    path = File.join @gemhome, path unless Pathname.new(path).absolute?
    dir = File.dirname path
    FileUtils.mkdir_p dir

    open path, 'wb' do |io|
      yield io if block_given?
    end

    path
  end

  def all_spec_names
    Gem::Specification.map(&:full_name)
  end

  ##
  # Creates a Gem::Specification with a minimum of extra work.  +name+ and
  # +version+ are the gem's name and version,  platform, author, email,
  # homepage, summary and description are defaulted.  The specification is
  # yielded for customization.
  #
  # The gem is added to the installed gems in +@gemhome+ and the runtime.
  #
  # Use this with #write_file to build an installed gem.

  def quick_gem(name, version='2')
    require 'rubygems/specification'

    spec = Gem::Specification.new do |s|
      s.platform    = Gem::Platform::RUBY
      s.name        = name
      s.version     = version
      s.author      = 'A User'
      s.email       = 'example@example.com'
      s.homepage    = 'http://example.com'
      s.summary     = "this is a summary"
      s.description = "This is a test description"

      yield(s) if block_given?
    end

    Gem::Specification.map # HACK: force specs to (re-)load before we write

    written_path = write_file spec.spec_file do |io|
      io.write spec.to_ruby_for_cache
    end

    spec.loaded_from = spec.loaded_from = written_path

    Gem::Specification.add_spec spec.for_cache

    return spec
  end

  def quick_spec name, version = '2'
    # TODO: deprecate
    require 'rubygems/specification'

    spec = Gem::Specification.new do |s|
      s.platform    = Gem::Platform::RUBY
      s.name        = name
      s.version     = version
      s.author      = 'A User'
      s.email       = 'example@example.com'
      s.homepage    = 'http://example.com'
      s.summary     = "this is a summary"
      s.description = "This is a test description"

      yield(s) if block_given?
    end

    spec.loaded_from = spec.spec_file

    Gem::Specification.add_spec spec

    return spec
  end

  ##
  # Builds a gem from +spec+ and places it in <tt>File.join @gemhome,
  # 'cache'</tt>.  Automatically creates files based on +spec.files+

  def util_build_gem(spec)
    dir = spec.gem_dir
    FileUtils.mkdir_p dir

    Dir.chdir dir do
      spec.files.each do |file|
        next if File.exist? file
        FileUtils.mkdir_p File.dirname(file)
        File.open file, 'w' do |fp| fp.puts "# #{file}" end
      end

      use_ui Gem::MockGemUi.new do
        Gem::Package.build spec
      end

      cache = spec.cache_file
      FileUtils.mv File.basename(cache), cache
    end
  end

  def util_remove_gem(spec)
    FileUtils.rm_rf spec.cache_file
    FileUtils.rm_rf spec.spec_file
  end

  ##
  # Removes all installed gems from +@gemhome+.

  def util_clear_gems
    FileUtils.rm_rf File.join(@gemhome, "gems") # TODO: use Gem::Dirs
    FileUtils.rm_rf File.join(@gemhome, "specifications")
    Gem::Specification.reset
  end

  ##
  # Install the provided specs

  def install_specs(*specs)
    Gem::Specification.add_specs(*specs)
    Gem.searcher = nil
  end

  ##
  # Installs the provided default specs including writing the spec file

  def install_default_gems(*specs)
    install_default_specs(*specs)

    specs.each do |spec|
      open spec.loaded_from, 'w' do |io|
        io.write spec.to_ruby_for_cache
      end
    end
  end

  ##
  # Install the provided default specs

  def install_default_specs(*specs)
    install_specs(*specs)
    specs.each do |spec|
      Gem.register_default_spec(spec)
    end
  end

  ##
  # Create a new spec (or gem if passed an array of files) and set it
  # up properly. Use this instead of util_spec and util_gem.

  def new_spec name, version, deps = nil, *files
    require 'rubygems/specification'

    spec = Gem::Specification.new do |s|
      s.platform    = Gem::Platform::RUBY
      s.name        = name
      s.version     = version
      s.author      = 'A User'
      s.email       = 'example@example.com'
      s.homepage    = 'http://example.com'
      s.summary     = "this is a summary"
      s.description = "This is a test description"

      Array(deps).each do |n, req|
        s.add_dependency n, (req || '>= 0')
      end

      s.files.push(*files) unless files.empty?

      yield s if block_given?
    end

    spec.loaded_from = spec.spec_file

    unless files.empty? then
      write_file spec.spec_file do |io|
        io.write spec.to_ruby_for_cache
      end

      util_build_gem spec

      cache_file = File.join @tempdir, 'gems', "#{spec.full_name}.gem"
      FileUtils.mkdir_p File.dirname cache_file
      FileUtils.mv spec.cache_file, cache_file
      FileUtils.rm spec.spec_file
    end

    spec
  end

  def new_default_spec(name, version, deps = nil, *files)
    spec = new_spec(name, version, deps)
    spec.loaded_from = File.join(@default_spec_dir, spec.spec_name)
    spec.files = files

    lib_dir = File.join(@tempdir, "default_gems", "lib")
    $LOAD_PATH.unshift(lib_dir)
    files.each do |file|
      rb_path = File.join(lib_dir, file)
      FileUtils.mkdir_p(File.dirname(rb_path))
      File.open(rb_path, "w") do |rb|
        rb << "# #{file}"
      end
    end

    spec
  end

  ##
  # Creates a spec with +name+, +version+ and +deps+.

  def util_spec(name, version, deps = nil, &block)
    # TODO: deprecate
    raise "deps or block, not both" if deps and block

    if deps then
      block = proc do |s|
        # Since Hash#each is unordered in 1.8, sort
        # the keys and iterate that way so the tests are
        # deteriminstic on all implementations.
        deps.keys.sort.each do |n|
          s.add_dependency n, (deps[n] || '>= 0')
        end
      end
    end

    quick_spec(name, version, &block)
  end

  ##
  # Creates a gem with +name+, +version+ and +deps+.  The specification will
  # be yielded before gem creation for customization.  The gem will be placed
  # in <tt>File.join @tempdir, 'gems'</tt>.  The specification and .gem file
  # location are returned.

  def util_gem(name, version, deps = nil, &block)
    # TODO: deprecate
    raise "deps or block, not both" if deps and block

    if deps then
      block = proc do |s|
        # Since Hash#each is unordered in 1.8, sort
        # the keys and iterate that way so the tests are
        # deterministic on all implementations.
        deps.keys.sort.each do |n|
          s.add_dependency n, (deps[n] || '>= 0')
        end
      end
    end

    spec = quick_gem(name, version, &block)

    util_build_gem spec

    cache_file = File.join @tempdir, 'gems', "#{spec.original_name}.gem"
    FileUtils.mkdir_p File.dirname cache_file
    FileUtils.mv spec.cache_file, cache_file
    FileUtils.rm spec.spec_file

    spec.loaded_from = nil

    [spec, cache_file]
  end

  ##
  # Gzips +data+.

  def util_gzip(data)
    out = StringIO.new

    Zlib::GzipWriter.wrap out do |io|
      io.write data
    end

    out.string
  end

  ##
  # Creates several default gems which all have a lib/code.rb file.  The gems
  # are not installed but are available in the cache dir.
  #
  # +@a1+:: gem a version 1, this is the best-described gem.
  # +@a2+:: gem a version 2
  # +@a3a:: gem a version 3.a
  # +@a_evil9+:: gem a_evil version 9, use this to ensure similarly-named gems
  #              don't collide with a.
  # +@b2+:: gem b version 2
  # +@c1_2+:: gem c version 1.2
  # +@pl1+:: gem pl version 1, this gem has a legacy platform of i386-linux.
  #
  # Additional +prerelease+ gems may also be created:
  #
  # +@a2_pre+:: gem a version 2.a
  # TODO: nuke this and fix tests. this should speed up a lot

  def util_make_gems(prerelease = false)
    @a1 = quick_gem 'a', '1' do |s|
      s.files = %w[lib/code.rb]
      s.require_paths = %w[lib]
      s.date = Gem::Specification::TODAY - 86400
      s.homepage = 'http://a.example.com'
      s.email = %w[example@example.com example2@example.com]
      s.authors = %w[Example Example2]
      s.description = <<-DESC
This line is really, really long.  So long, in fact, that it is more than eighty characters long!  The purpose of this line is for testing wrapping behavior because sometimes people don't wrap their text to eighty characters.  Without the wrapping, the text might not look good in the RSS feed.

Also, a list:
  * An entry that\'s actually kind of sort
  * an entry that\'s really long, which will probably get wrapped funny.  That's ok, somebody wasn't thinking straight when they made it more than eighty characters.
      DESC
    end

    init = proc do |s|
      s.files = %w[lib/code.rb]
      s.require_paths = %w[lib]
    end

    @a2      = quick_gem('a', '2',      &init)
    @a3a     = quick_gem('a', '3.a',    &init)
    @a_evil9 = quick_gem('a_evil', '9', &init)
    @b2      = quick_gem('b', '2',      &init)
    @c1_2    = quick_gem('c', '1.2',    &init)
    @x       = quick_gem('x', '1', &init)
    @dep_x   = quick_gem('dep_x', '1') do |s|
      s.files = %w[lib/code.rb]
      s.require_paths = %w[lib]
      s.add_dependency 'x', '>= 1'
    end

    @pl1     = quick_gem 'pl', '1' do |s| # l for legacy
      s.files = %w[lib/code.rb]
      s.require_paths = %w[lib]
      s.platform = Gem::Platform.new 'i386-linux'
      s.instance_variable_set :@original_platform, 'i386-linux'
    end

    if prerelease
      @a2_pre = quick_gem('a', '2.a', &init)
      write_file File.join(*%W[gems #{@a2_pre.original_name} lib code.rb])
      util_build_gem @a2_pre
    end

    write_file File.join(*%W[gems #{@a1.original_name}   lib code.rb])
    write_file File.join(*%W[gems #{@a2.original_name}   lib code.rb])
    write_file File.join(*%W[gems #{@a3a.original_name}  lib code.rb])
    write_file File.join(*%W[gems #{@b2.original_name}   lib code.rb])
    write_file File.join(*%W[gems #{@c1_2.original_name} lib code.rb])
    write_file File.join(*%W[gems #{@pl1.original_name}  lib code.rb])
    write_file File.join(*%W[gems #{@x.original_name}  lib code.rb])
    write_file File.join(*%W[gems #{@dep_x.original_name}  lib code.rb])

    [@a1, @a2, @a3a, @a_evil9, @b2, @c1_2, @pl1, @x, @dep_x].each do |spec|
      util_build_gem spec
    end

    FileUtils.rm_r File.join(@gemhome, "gems", @pl1.original_name)
  end

  ##
  # Set the platform to +arch+

  def util_set_arch(arch)
    Gem::ConfigMap[:arch] = arch
    platform = Gem::Platform.new arch

    Gem.instance_variable_set :@platforms, nil
    Gem::Platform.instance_variable_set :@local, nil

    platform
  end

  ##
  # Sets up a fake fetcher using the gems from #util_make_gems.  Optionally
  # additional +prerelease+ gems may be included.
  #
  # Gems created by this method may be fetched using Gem::RemoteFetcher.

  def util_setup_fake_fetcher(prerelease = false)
    require 'zlib'
    require 'socket'
    require 'rubygems/remote_fetcher'

    @fetcher = Gem::FakeFetcher.new

    util_make_gems(prerelease)
    Gem::Specification.reset

    @all_gems = [@a1, @a2, @a3a, @a_evil9, @b2, @c1_2].sort
    @all_gem_names = @all_gems.map { |gem| gem.full_name }

    gem_names = [@a1.full_name, @a2.full_name, @a3a.full_name, @b2.full_name]
    @gem_names = gem_names.sort.join("\n")

    Gem::RemoteFetcher.fetcher = @fetcher
  end

  ##
  # Add +spec+ to +@fetcher+ serving the data in the file +path+.
  # +repo+ indicates which repo to make +spec+ appear to be in.

  def add_to_fetcher(spec, path=nil, repo=@gem_repo)
    path ||= spec.cache_file
    @fetcher.data["#{@gem_repo}gems/#{spec.file_name}"] = read_binary(path)
  end

  ##
  # Sets up Gem::SpecFetcher to return information from the gems in +specs+.
  # Best used with +@all_gems+ from #util_setup_fake_fetcher.

  def util_setup_spec_fetcher(*specs)
    specs -= Gem::Specification._all
    Gem::Specification.add_specs(*specs)

    spec_fetcher = Gem::SpecFetcher.fetcher

    prerelease, all = Gem::Specification.partition { |spec|
      spec.version.prerelease?
    }

    spec_fetcher.specs[@uri] = []
    all.each do |spec|
      spec_fetcher.specs[@uri] << spec.name_tuple
    end

    spec_fetcher.latest_specs[@uri] = []
    Gem::Specification.latest_specs.each do |spec|
      spec_fetcher.latest_specs[@uri] << spec.name_tuple
    end

    spec_fetcher.prerelease_specs[@uri] = []
    prerelease.each do |spec|
      spec_fetcher.prerelease_specs[@uri] << spec.name_tuple
    end

    v = Gem.marshal_version

    Gem::Specification.each do |spec|
      path = "#{@gem_repo}quick/Marshal.#{v}/#{spec.original_name}.gemspec.rz"
      data = Marshal.dump spec
      data_deflate = Zlib::Deflate.deflate data
      @fetcher.data[path] = data_deflate
    end unless Gem::RemoteFetcher === @fetcher # HACK for test_download_to_cache

    nil # force errors
  end

  ##
  # Deflates +data+

  def util_zip(data)
    Zlib::Deflate.deflate data
  end

  ##
  # Is this test being run on a Windows platform?

  def self.win_platform?
    Gem.win_platform?
  end

  ##
  # Is this test being run on a Windows platform?

  def win_platform?
    Gem.win_platform?
  end

  ##
  # Returns whether or not we're on a version of Ruby built with VC++ (or
  # Borland) versus Cygwin, Mingw, etc.

  def self.vc_windows?
    RUBY_PLATFORM.match('mswin')
  end

  ##
  # Returns whether or not we're on a version of Ruby built with VC++ (or
  # Borland) versus Cygwin, Mingw, etc.

  def vc_windows?
    RUBY_PLATFORM.match('mswin')
  end

  ##
  # Returns the make command for the current platform. For versions of Ruby
  # built on MS Windows with VC++ or Borland it will return 'nmake'. On all
  # other platforms, including Cygwin, it will return 'make'.

  def self.make_command
    ENV["make"] || (vc_windows? ? 'nmake' : 'make')
  end

  ##
  # Returns the make command for the current platform. For versions of Ruby
  # built on MS Windows with VC++ or Borland it will return 'nmake'. On all
  # other platforms, including Cygwin, it will return 'make'.

  def make_command
    ENV["make"] || (vc_windows? ? 'nmake' : 'make')
  end

  ##
  # Returns whether or not the nmake command could be found.

  def nmake_found?
    system('nmake /? 1>NUL 2>&1')
  end

  # In case we're building docs in a background process, this method waits for
  # that process to exit (or if it's already been reaped, or never happened,
  # swallows the Errno::ECHILD error).
  def wait_for_child_process_to_exit
    Process.wait if Process.respond_to?(:fork)
  rescue Errno::ECHILD
  end

  ##
  # Allows tests to use a random (but controlled) port number instead of
  # a hardcoded one. This helps CI tools when running parallels builds on
  # the same builder slave.

  def self.process_based_port
    @@process_based_port ||= 8000 + $$ % 1000
  end

  ##
  # See ::process_based_port

  def process_based_port
    self.class.process_based_port
  end

  ##
  # Allows the proper version of +rake+ to be used for the test.

  def build_rake_in(good=true)
    gem_ruby = Gem.ruby
    Gem.ruby = @@ruby
    env_rake = ENV["rake"]
    rake = (good ? @@good_rake : @@bad_rake)
    ENV["rake"] = rake
    yield rake
  ensure
    Gem.ruby = gem_ruby
    if env_rake
      ENV["rake"] = env_rake
    else
      ENV.delete("rake")
    end
  end

  ##
  # Finds the path to the ruby executable

  def self.rubybin
    ruby = ENV["RUBY"]
    return ruby if ruby
    ruby = "ruby"
    rubyexe = "#{ruby}.exe"

    3.times do
      if File.exist? ruby and File.executable? ruby and !File.directory? ruby
        return File.expand_path(ruby)
      end
      if File.exist? rubyexe and File.executable? rubyexe
        return File.expand_path(rubyexe)
      end
      ruby = File.join("..", ruby)
    end

    begin
      require "rbconfig"
      File.join(RbConfig::CONFIG["bindir"],
                RbConfig::CONFIG["ruby_install_name"] +
                RbConfig::CONFIG["EXEEXT"])
    rescue LoadError
      "ruby"
    end
  end

  @@ruby = rubybin
  @@good_rake = "#{rubybin} #{File.expand_path('../../../test/rubygems/good_rake.rb', __FILE__)}"
  @@bad_rake = "#{rubybin} #{File.expand_path('../../../test/rubygems/bad_rake.rb', __FILE__)}"

  ##
  # Construct a new Gem::Dependency.

  def dep name, *requirements
    Gem::Dependency.new name, *requirements
  end

  ##
  # Constructs a new Gem::Requirement.

  def req *requirements
    return requirements.first if Gem::Requirement === requirements.first
    Gem::Requirement.create requirements
  end

  ##
  # Constructs a new Gem::Specification.

  def spec name, version, &block
    Gem::Specification.new name, v(version), &block
  end

  ##
  # Construct a new Gem::Version.

  def v string
    Gem::Version.create string
  end

  class StaticSet
    def initialize(specs)
      @specs = specs.sort_by { |s| s.full_name }
    end

    def find_spec(dep)
      @specs.reverse_each do |s|
        return s if dep.matches_spec? s
      end
    end

    def find_all(dep)
      @specs.find_all { |s| dep.matches_spec? s }
    end

    def prefetch(reqs)
    end
  end

  ##
  # Loads certificate named +cert_name+ from <tt>test/rubygems/</tt>.

  def self.load_cert cert_name
    cert_file = cert_path cert_name

    cert = File.read cert_file

    OpenSSL::X509::Certificate.new cert
  end

  ##
  # Returns the path to the certificate named +cert_name+ from
  # <tt>test/rubygems/</tt>.

  def self.cert_path cert_name
    if 32 == (Time.at(2**32) rescue 32) then
      cert_file =
        File.expand_path "../../../test/rubygems/#{cert_name}_cert_32.pem",
                         __FILE__

      return cert_file if File.exist? cert_file
    end

    File.expand_path "../../../test/rubygems/#{cert_name}_cert.pem", __FILE__
  end

  ##
  # Loads an RSA private key named +key_name+ in <tt>test/rubygems/</tt>

  def self.load_key key_name
    key_file = key_path key_name

    key = File.read key_file

    OpenSSL::PKey::RSA.new key
  end

  ##
  # Returns the path tot he key named +key_name+ from <tt>test/rubygems</tt>

  def self.key_path key_name
    File.expand_path "../../../test/rubygems/#{key_name}_key.pem", __FILE__
  end

  # :stopdoc:
  # only available in RubyGems tests

  begin
    PRIVATE_KEY      = load_key 'private'
    PRIVATE_KEY_PATH = key_path 'private'
    PUBLIC_KEY       = PRIVATE_KEY.public_key

    PUBLIC_CERT      = load_cert 'public'
    PUBLIC_CERT_PATH = cert_path 'public'
  rescue Errno::ENOENT
    PRIVATE_KEY = nil
    PUBLIC_KEY  = nil
    PUBLIC_CERT = nil
  end

end
