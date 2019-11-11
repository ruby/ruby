# frozen_string_literal: true

require 'rubygems'

# If bundler gemspec exists, add to stubs
bundler_gemspec = File.expand_path("../../../bundler/bundler.gemspec", __FILE__)
if File.exist?(bundler_gemspec)
  Gem::Specification.dirs.unshift File.dirname(bundler_gemspec)
  Gem::Specification.class_variable_set :@@stubs, nil
  Gem::Specification.stubs
  Gem::Specification.dirs.shift
end

begin
  gem 'minitest', '~> 5.0'
rescue Gem::LoadError
end

begin
  require 'simplecov'
  SimpleCov.start do
    add_filter "/test/"
    add_filter "/bundler/"
    add_filter "/lib/rubygems/resolver/molinillo"
  end
rescue LoadError
end

require 'bundler'

require 'minitest/autorun'

require 'rubygems/deprecate'

require 'fileutils'
require 'pathname'
require 'pp'
require 'rubygems/package'
require 'shellwords'
require 'tmpdir'
require 'uri'
require 'zlib'
require 'benchmark' # stdlib
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
  # Allows setting path to Ruby.  This method is available when requiring
  # 'rubygems/test_case'

  def self.ruby=(ruby)
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

class Gem::TestCase < (defined?(Minitest::Test) ? Minitest::Test : MiniTest::Unit::TestCase)

  extend Gem::Deprecate

  attr_accessor :fetcher # :nodoc:

  attr_accessor :gem_repo # :nodoc:

  attr_accessor :uri # :nodoc:

  TEST_PATH = ENV.fetch('RUBYGEMS_TEST_PATH', File.expand_path('../../../test/rubygems', __FILE__))

  def assert_activate(expected, *specs)
    specs.each do |spec|
      case spec
      when String then
        Gem::Specification.find_by_name(spec).activate
      when Gem::Specification then
        spec.activate
      else
        flunk spec.inspect
      end
    end

    loaded = Gem.loaded_specs.values.map(&:full_name)

    assert_equal expected.sort, loaded.sort if expected
  end

  # TODO: move to minitest
  def assert_path_exists(path, msg = nil)
    msg = message(msg) { "Expected path '#{path}' to exist" }
    assert File.exist?(path), msg
  end

  def assert_directory_exists(path, msg = nil)
    msg = message(msg) { "Expected path '#{path}' to be a directory" }
    assert_path_exists path
    assert File.directory?(path), msg
  end

  ##
  # Sets the ENABLE_SHARED entry in RbConfig::CONFIG to +value+ and restores
  # the original value when the block ends

  def enable_shared(value)
    enable_shared = RbConfig::CONFIG['ENABLE_SHARED']
    RbConfig::CONFIG['ENABLE_SHARED'] = value

    yield
  ensure
    if enable_shared
      RbConfig::CONFIG['enable_shared'] = enable_shared
    else
      RbConfig::CONFIG.delete 'enable_shared'
    end
  end

  ##
  # Sets the vendordir entry in RbConfig::CONFIG to +value+ and restores the
  # original value when the block ends
  #
  def vendordir(value)
    vendordir = RbConfig::CONFIG['vendordir']

    if value
      RbConfig::CONFIG['vendordir'] = value
    else
      RbConfig::CONFIG.delete 'vendordir'
    end

    yield
  ensure
    if vendordir
      RbConfig::CONFIG['vendordir'] = vendordir
    else
      RbConfig::CONFIG.delete 'vendordir'
    end
  end

  # TODO: move to minitest
  def refute_path_exists(path, msg = nil)
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
      msg = message(msg) do
        'Expected output containing make command "%s": %s' % [
          ('%s %s' % [make_command, target]).rstrip,
          output.inspect
        ]
      end
    else
      msg = message(msg) do
        'Expected make command "%s": %s' % [
          ('%s %s' % [make_command, target]).rstrip,
          output.inspect
        ]
      end
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

  ##
  # #setup prepares a sandboxed location to install gems.  All installs are
  # directed to a temporary directory.  All install plugins are removed.
  #
  # If the +RUBY+ environment variable is set the given path is used for
  # Gem::ruby.  The local platform is set to <tt>i386-mswin32</tt> for Windows
  # or <tt>i686-darwin8.10.1</tt> otherwise.

  def setup
    super

    @orig_env = ENV.to_hash

    ENV['GEM_VENDOR'] = nil
    ENV['GEMRC'] = nil
    ENV['SOURCE_DATE_EPOCH'] = nil

    @current_dir = Dir.pwd
    @fetcher     = nil

    @back_ui                       = Gem::DefaultUserInteraction.ui
    @ui                            = Gem::MockGemUi.new
    # This needs to be a new instance since we call use_ui(@ui) when we want to
    # capture output
    Gem::DefaultUserInteraction.ui = Gem::MockGemUi.new

    tmpdir = File.realpath Dir.tmpdir
    tmpdir.tap(&Gem::UNTAINT)

    @tempdir = File.join(tmpdir, "test_rubygems_#{$$}")
    @tempdir.tap(&Gem::UNTAINT)

    FileUtils.mkdir_p @tempdir

    # This makes the tempdir consistent on Windows.
    # Dir.tmpdir may return short path name, but Dir[Dir.tmpdir] returns long
    # path name. https://bugs.ruby-lang.org/issues/10819
    # File.expand_path or File.realpath doesn't convert path name to long path
    # name. Only Dir[] (= Dir.glob) works.
    # Short and long path name is specific to Windows filesystem.
    if win_platform?
      @tempdir = Dir[@tempdir][0]
      @tempdir.tap(&Gem::UNTAINT)
    end

    @gemhome  = File.join @tempdir, 'gemhome'
    @userhome = File.join @tempdir, 'userhome'
    ENV["GEM_SPEC_CACHE"] = File.join @tempdir, 'spec_cache'

    @orig_ruby = if ENV['RUBY']
                   ruby = Gem.ruby
                   Gem.ruby = ENV['RUBY']
                   ruby
                 end

    @git = ENV['GIT'] || 'git'

    Gem.ensure_gem_subdirectories @gemhome

    @orig_LOAD_PATH = $LOAD_PATH.dup
    $LOAD_PATH.map! do |s|
      expand_path = File.realpath(s) rescue File.expand_path(s)
      if expand_path != s
        expand_path.tap(&Gem::UNTAINT)
        if s.instance_variable_defined?(:@gem_prelude_index)
          expand_path.instance_variable_set(:@gem_prelude_index, expand_path)
        end
        expand_path.freeze if s.frozen?
        s = expand_path
      end
      s
    end

    Dir.chdir @tempdir

    ENV['HOME'] = @userhome
    Gem.instance_variable_set :@user_home, nil
    Gem.instance_variable_set :@gemdeps, nil
    Gem.instance_variable_set :@env_requirements_by_name, nil
    Gem.send :remove_instance_variable, :@ruby_version if
      Gem.instance_variables.include? :@ruby_version

    FileUtils.mkdir_p @gemhome
    FileUtils.mkdir_p @userhome

    ENV['GEM_PRIVATE_KEY_PASSPHRASE'] = PRIVATE_KEY_PASSPHRASE

    @default_dir = File.join @tempdir, 'default'
    @default_spec_dir = File.join @default_dir, "specifications", "default"
    if Gem.java_platform?
      @orig_default_gem_home = RbConfig::CONFIG['default_gem_home']
      RbConfig::CONFIG['default_gem_home'] = @default_dir
    else
      Gem.instance_variable_set(:@default_dir, @default_dir)
    end
    FileUtils.mkdir_p @default_spec_dir

    Gem::Specification.unresolved_deps.clear
    Gem.use_paths(@gemhome)

    Gem::Security.reset

    Gem.loaded_specs.clear
    Gem.clear_default_specs
    Bundler.reset!

    Gem.configuration.verbose = true
    Gem.configuration.update_sources = true

    Gem::RemoteFetcher.fetcher = Gem::FakeFetcher.new

    @gem_repo = "http://gems.example.com/"
    @uri = URI.parse @gem_repo
    Gem.sources.replace [@gem_repo]

    Gem.searcher = nil
    Gem::SpecFetcher.fetcher = nil

    @orig_arch = RbConfig::CONFIG['arch']

    if win_platform?
      util_set_arch 'i386-mswin32'
    else
      util_set_arch 'i686-darwin8.10.1'
    end

    @orig_hooks = {}
    %w[post_install_hooks done_installing_hooks post_uninstall_hooks pre_uninstall_hooks pre_install_hooks pre_reset_hooks post_reset_hooks post_build_hooks].each do |name|
      @orig_hooks[name] = Gem.send(name).dup
    end

    @marshal_version = "#{Marshal::MAJOR_VERSION}.#{Marshal::MINOR_VERSION}"
    @orig_LOADED_FEATURES = $LOADED_FEATURES.dup
  end

  ##
  # #teardown restores the process to its original state and removes the
  # tempdir

  def teardown
    $LOAD_PATH.replace @orig_LOAD_PATH if @orig_LOAD_PATH
    if @orig_LOADED_FEATURES
      if @orig_LOAD_PATH
        paths = @orig_LOAD_PATH.map {|path| File.join(File.expand_path(path), "/")}
        ($LOADED_FEATURES - @orig_LOADED_FEATURES).each do |feat|
          unless paths.any? {|path| feat.start_with?(path)}
            $LOADED_FEATURES.delete(feat)
          end
        end
      else
        $LOADED_FEATURES.replace @orig_LOADED_FEATURES
      end
    end

    RbConfig::CONFIG['arch'] = @orig_arch

    if defined? Gem::RemoteFetcher
      Gem::RemoteFetcher.fetcher = nil
    end

    Dir.chdir @current_dir

    FileUtils.rm_rf @tempdir

    ENV.replace(@orig_env)

    Gem.ruby = @orig_ruby if @orig_ruby

    if Gem.java_platform?
      RbConfig::CONFIG['default_gem_home'] = @orig_default_gem_home
    else
      Gem.instance_variable_set :@default_dir, nil
    end

    Gem::Specification._clear_load_cache
    Gem::Specification.unresolved_deps.clear
    Gem::refresh

    @orig_hooks.each do |name, hooks|
      Gem.send(name).replace hooks
    end

    @back_ui.close
  end

  def common_installer_setup
    common_installer_teardown

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

  def common_installer_teardown
    Gem.post_build_hooks.clear
    Gem.post_install_hooks.clear
    Gem.done_installing_hooks.clear
    Gem.post_reset_hooks.clear
    Gem.post_uninstall_hooks.clear
    Gem.pre_install_hooks.clear
    Gem.pre_reset_hooks.clear
    Gem.pre_uninstall_hooks.clear
  end

  ##
  # A git_gem is used with a gem dependencies file.  The gem created here
  # has no files, just a gem specification for the given +name+ and +version+.
  #
  # Yields the +specification+ to the block, if given

  def git_gem(name = 'a', version = 1)
    have_git?

    directory = File.join 'git', name
    directory = File.expand_path directory

    git_spec = Gem::Specification.new name, version do |specification|
      yield specification if block_given?
    end

    FileUtils.mkdir_p directory

    gemspec = "#{name}.gemspec"

    File.open File.join(directory, gemspec), 'w' do |io|
      io.write git_spec.to_ruby
    end

    head = nil

    Dir.chdir directory do
      unless File.exist? '.git'
        system @git, 'init', '--quiet'
        system @git, 'config', 'user.name',  'RubyGems Tests'
        system @git, 'config', 'user.email', 'rubygems@example'
      end

      system @git, 'add', gemspec
      system @git, 'commit', '-a', '-m', 'a non-empty commit message', '--quiet'
      head = Gem::Util.popen(@git, 'rev-parse', 'master').strip
    end

    return name, git_spec.version, directory, head
  end

  ##
  # Skips this test unless you have a git executable

  def have_git?
    return if in_path? @git

    skip 'cannot find git executable, use GIT environment variable to set'
  end

  def in_path?(executable) # :nodoc:
    return true if %r%\A([A-Z]:|/)% =~ executable and File.exist? executable

    ENV['PATH'].split(File::PATH_SEPARATOR).any? do |directory|
      File.exist? File.join directory, executable
    end
  end

  ##
  # Builds and installs the Gem::Specification +spec+

  def install_gem(spec, options = {})
    require 'rubygems/installer'

    gem = File.join @tempdir, "gems", "#{spec.full_name}.gem"

    unless File.exist? gem
      use_ui Gem::MockGemUi.new do
        Dir.chdir @tempdir do
          Gem::Package.build spec
        end
      end

      gem = File.join(@tempdir, File.basename(spec.cache_file)).tap(&Gem::UNTAINT)
    end

    Gem::Installer.at(gem, options.merge({:wrappers => true})).install
  end

  ##
  # Builds and installs the Gem::Specification +spec+ into the user dir

  def install_gem_user(spec)
    install_gem spec, :user_install => true
  end

  ##
  # Uninstalls the Gem::Specification +spec+
  def uninstall_gem(spec)
    require 'rubygems/uninstaller'

    Class.new(Gem::Uninstaller) do
      def ask_if_ok(spec)
        true
      end
    end.new(spec.name, :executables => true, :user_install => true).uninstall
  end

  ##
  # Enables pretty-print for all tests

  def mu_pp(obj)
    s = String.new
    s = PP.pp obj, s
    s = s.force_encoding(Encoding.default_external)
    s.chomp
  end

  ##
  # Reads a Marshal file at +path+

  def read_cache(path)
    File.open path.dup.tap(&Gem::UNTAINT), 'rb' do |io|
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
    FileUtils.mkdir_p dir unless File.directory? dir

    File.open path, 'wb' do |io|
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

    spec.loaded_from = written_path

    Gem::Specification.reset

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

        File.open file, 'w' do |fp|
          fp.puts "# #{file}"
        end
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
    FileUtils.rm_rf File.join(@gemhome, "gems")
    FileUtils.mkdir File.join(@gemhome, "gems")
    FileUtils.rm_rf File.join(@gemhome, "specifications")
    FileUtils.mkdir File.join(@gemhome, "specifications")
    Gem::Specification.reset
  end

  ##
  # Install the provided specs

  def install_specs(*specs)
    specs.each do |spec|
      Gem::Installer.for_spec(spec).install
    end

    Gem.searcher = nil
  end

  ##
  # Installs the provided default specs including writing the spec file

  def install_default_gems(*specs)
    install_default_specs(*specs)

    specs.each do |spec|
      File.open spec.loaded_from, 'w' do |io|
        io.write spec.to_ruby_for_cache
      end
    end
  end

  ##
  # Install the provided default specs

  def install_default_specs(*specs)
    specs.each do |spec|
      installer = Gem::Installer.for_spec(spec, :install_as_default => true)
      installer.install
      Gem.register_default_spec(spec)
    end
  end

  def loaded_spec_names
    Gem.loaded_specs.values.map(&:full_name).sort
  end

  def unresolved_names
    Gem::Specification.unresolved_deps.values.map(&:to_s).sort
  end

  def save_loaded_features
    old_loaded_features = $LOADED_FEATURES.dup
    yield
  ensure
    prefix = File.dirname(__FILE__) + "/"
    new_features = ($LOADED_FEATURES - old_loaded_features)
    old_loaded_features.concat(new_features.select {|f| f.rindex(prefix, 0)})
    $LOADED_FEATURES.replace old_loaded_features
  end

  def new_default_spec(name, version, deps = nil, *files)
    spec = util_spec name, version, deps

    spec.loaded_from = File.join(@default_spec_dir, spec.spec_name)
    spec.files = files

    lib_dir = File.join(@tempdir, "default_gems", "lib")
    lib_dir.instance_variable_set(:@gem_prelude_index, lib_dir)
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
  # Creates a spec with +name+, +version+.  +deps+ can specify the dependency
  # or a +block+ can be given for full customization of the specification.

  def util_spec(name, version = 2, deps = nil, *files) # :yields: specification
    raise "deps or block, not both" if deps and block_given?

    spec = Gem::Specification.new do |s|
      s.platform    = Gem::Platform::RUBY
      s.name        = name
      s.version     = version
      s.author      = 'A User'
      s.email       = 'example@example.com'
      s.homepage    = 'http://example.com'
      s.summary     = "this is a summary"
      s.description = "This is a test description"

      s.files.push(*files) unless files.empty?

      yield s if block_given?
    end

    if deps
      # Since Hash#each is unordered in 1.8, sort the keys and iterate that
      # way so the tests are deterministic on all implementations.
      deps.keys.sort.each do |n|
        spec.add_dependency n, (deps[n] || '>= 0')
      end
    end

    unless files.empty?
      write_file spec.spec_file do |io|
        io.write spec.to_ruby_for_cache
      end

      util_build_gem spec

      cache_file = File.join @tempdir, 'gems', "#{spec.full_name}.gem"
      FileUtils.mkdir_p File.dirname cache_file
      FileUtils.mv spec.cache_file, cache_file
      FileUtils.rm spec.spec_file
    end

    return spec
  end

  ##
  # Creates a gem with +name+, +version+ and +deps+.  The specification will
  # be yielded before gem creation for customization.  The gem will be placed
  # in <tt>File.join @tempdir, 'gems'</tt>.  The specification and .gem file
  # location are returned.

  def util_gem(name, version, deps = nil, &block)
    if deps
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
    @x       = quick_gem('x', '1',      &init)
    @dep_x   = quick_gem('dep_x', '1') do |s|
      s.files = %w[lib/code.rb]
      s.require_paths = %w[lib]
      s.add_dependency 'x', '>= 1'
    end

    @pl1 = quick_gem 'pl', '1' do |s| # l for legacy
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

    write_file File.join(*%W[gems #{@a1.original_name}      lib code.rb])
    write_file File.join(*%W[gems #{@a2.original_name}      lib code.rb])
    write_file File.join(*%W[gems #{@a3a.original_name}     lib code.rb])
    write_file File.join(*%W[gems #{@a_evil9.original_name} lib code.rb])
    write_file File.join(*%W[gems #{@b2.original_name}      lib code.rb])
    write_file File.join(*%W[gems #{@c1_2.original_name}    lib code.rb])
    write_file File.join(*%W[gems #{@pl1.original_name}     lib code.rb])
    write_file File.join(*%W[gems #{@x.original_name}       lib code.rb])
    write_file File.join(*%W[gems #{@dep_x.original_name}   lib code.rb])

    [@a1, @a2, @a3a, @a_evil9, @b2, @c1_2, @pl1, @x, @dep_x].each do |spec|
      util_build_gem spec
    end

    FileUtils.rm_r File.join(@gemhome, "gems", @pl1.original_name)
  end

  ##
  # Set the platform to +arch+

  def util_set_arch(arch)
    RbConfig::CONFIG['arch'] = arch
    platform = Gem::Platform.new arch

    Gem.instance_variable_set :@platforms, nil
    Gem::Platform.instance_variable_set :@local, nil

    yield if block_given?

    platform
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

  def util_setup_spec_fetcher(*specs)
    all_specs = Gem::Specification.to_a + specs
    Gem::Specification._resort! all_specs

    spec_fetcher = Gem::SpecFetcher.fetcher

    prerelease, all = all_specs.partition { |spec| spec.version.prerelease?  }
    latest = Gem::Specification._latest_specs all_specs

    spec_fetcher.specs[@uri] = []
    all.each do |spec|
      spec_fetcher.specs[@uri] << spec.name_tuple
    end

    spec_fetcher.latest_specs[@uri] = []
    latest.each do |spec|
      spec_fetcher.latest_specs[@uri] << spec.name_tuple
    end

    spec_fetcher.prerelease_specs[@uri] = []
    prerelease.each do |spec|
      spec_fetcher.prerelease_specs[@uri] << spec.name_tuple
    end

    # HACK for test_download_to_cache
    unless Gem::RemoteFetcher === @fetcher
      v = Gem.marshal_version

      specs = all.map { |spec| spec.name_tuple }
      s_zip = util_gzip Marshal.dump Gem::NameTuple.to_basic specs

      latest_specs = latest.map do |spec|
        spec.name_tuple
      end

      l_zip = util_gzip Marshal.dump Gem::NameTuple.to_basic latest_specs

      prerelease_specs = prerelease.map { |spec| spec.name_tuple }
      p_zip = util_gzip Marshal.dump Gem::NameTuple.to_basic prerelease_specs

      @fetcher.data["#{@gem_repo}specs.#{v}.gz"]            = s_zip
      @fetcher.data["#{@gem_repo}latest_specs.#{v}.gz"]     = l_zip
      @fetcher.data["#{@gem_repo}prerelease_specs.#{v}.gz"] = p_zip

      v = Gem.marshal_version

      all_specs.each do |spec|
        path = "#{@gem_repo}quick/Marshal.#{v}/#{spec.original_name}.gemspec.rz"
        data = Marshal.dump spec
        data_deflate = Zlib::Deflate.deflate data
        @fetcher.data[path] = data_deflate
      end
    end

    nil # force errors
  end

  ##
  # Deflates +data+

  def util_zip(data)
    Zlib::Deflate.deflate data
  end

  def util_set_RUBY_VERSION(version, patchlevel = nil, revision = nil, description = nil, engine = "ruby", engine_version = nil)
    if Gem.instance_variables.include? :@ruby_version
      Gem.send :remove_instance_variable, :@ruby_version
    end

    @RUBY_VERSION        = RUBY_VERSION
    @RUBY_PATCHLEVEL     = RUBY_PATCHLEVEL     if defined?(RUBY_PATCHLEVEL)
    @RUBY_REVISION       = RUBY_REVISION       if defined?(RUBY_REVISION)
    @RUBY_DESCRIPTION    = RUBY_DESCRIPTION    if defined?(RUBY_DESCRIPTION)
    @RUBY_ENGINE         = RUBY_ENGINE
    @RUBY_ENGINE_VERSION = RUBY_ENGINE_VERSION if defined?(RUBY_ENGINE_VERSION)

    util_clear_RUBY_VERSION

    Object.const_set :RUBY_VERSION,        version
    Object.const_set :RUBY_PATCHLEVEL,     patchlevel     if patchlevel
    Object.const_set :RUBY_REVISION,       revision       if revision
    Object.const_set :RUBY_DESCRIPTION,    description    if description
    Object.const_set :RUBY_ENGINE,         engine
    Object.const_set :RUBY_ENGINE_VERSION, engine_version if engine_version
  end

  def util_restore_RUBY_VERSION
    util_clear_RUBY_VERSION

    Object.const_set :RUBY_VERSION,        @RUBY_VERSION
    Object.const_set :RUBY_PATCHLEVEL,     @RUBY_PATCHLEVEL  if
      defined?(@RUBY_PATCHLEVEL)
    Object.const_set :RUBY_REVISION,       @RUBY_REVISION    if
      defined?(@RUBY_REVISION)
    Object.const_set :RUBY_DESCRIPTION,    @RUBY_DESCRIPTION if
      defined?(@RUBY_DESCRIPTION)
    Object.const_set :RUBY_ENGINE,         @RUBY_ENGINE
    Object.const_set :RUBY_ENGINE_VERSION, @RUBY_ENGINE_VERSION if
      defined?(@RUBY_ENGINE_VERSION)
  end

  def util_clear_RUBY_VERSION
    Object.send :remove_const, :RUBY_VERSION
    Object.send :remove_const, :RUBY_PATCHLEVEL     if defined?(RUBY_PATCHLEVEL)
    Object.send :remove_const, :RUBY_REVISION       if defined?(RUBY_REVISION)
    Object.send :remove_const, :RUBY_DESCRIPTION    if defined?(RUBY_DESCRIPTION)
    Object.send :remove_const, :RUBY_ENGINE
    Object.send :remove_const, :RUBY_ENGINE_VERSION if defined?(RUBY_ENGINE_VERSION)
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
  # Is this test being run on a Java platform?

  def self.java_platform?
    Gem.java_platform?
  end

  ##
  # Is this test being run on a Java platform?

  def java_platform?
    Gem.java_platform?
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
    ENV["make"] || ENV["MAKE"] || (vc_windows? ? 'nmake' : 'make')
  end

  ##
  # Returns the make command for the current platform. For versions of Ruby
  # built on MS Windows with VC++ or Borland it will return 'nmake'. On all
  # other platforms, including Cygwin, it will return 'make'.

  def make_command
    ENV["make"] || ENV["MAKE"] || (vc_windows? ? 'nmake' : 'make')
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
  # Finds the path to the Ruby executable

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

  class << self

    # :nodoc:
    ##
    # Return the join path, with escaping backticks, dollars, and
    # double-quotes.  Unlike `shellescape`, equal-sign is not escaped.
    private

    def escape_path(*path)
      path = File.join(*path)
      if %r'\A[-+:/=@,.\w]+\z' =~ path
        path
      else
        "\"#{path.gsub(/[`$"]/, '\\&')}\""
      end
    end

  end

  @@ruby = rubybin
  @@good_rake = "#{rubybin} #{escape_path(TEST_PATH, 'good_rake.rb')}"
  @@bad_rake = "#{rubybin} #{escape_path(TEST_PATH, 'bad_rake.rb')}"

  ##
  # Construct a new Gem::Dependency.

  def dep(name, *requirements)
    Gem::Dependency.new name, *requirements
  end

  ##
  # Constructs a Gem::Resolver::DependencyRequest from a
  # Gem::Dependency +dep+, a +from_name+ and +from_version+ requesting the
  # dependency and a +parent+ DependencyRequest

  def dependency_request(dep, from_name, from_version, parent = nil)
    remote = Gem::Source.new @uri

    unless parent
      parent_dep = dep from_name, from_version
      parent = Gem::Resolver::DependencyRequest.new parent_dep, nil
    end

    spec = Gem::Resolver::IndexSpecification.new \
      nil, from_name, from_version, remote, Gem::Platform::RUBY
    activation = Gem::Resolver::ActivationRequest.new spec, parent

    Gem::Resolver::DependencyRequest.new dep, activation
  end

  ##
  # Constructs a new Gem::Requirement.

  def req(*requirements)
    return requirements.first if Gem::Requirement === requirements.first
    Gem::Requirement.create requirements
  end

  ##
  # Constructs a new Gem::Specification.

  def spec(name, version, &block)
    Gem::Specification.new name, v(version), &block
  end

  ##
  # Creates a SpecFetcher pre-filled with the gems or specs defined in the
  # block.
  #
  # Yields a +fetcher+ object that responds to +spec+ and +gem+.  +spec+ adds
  # a specification to the SpecFetcher while +gem+ adds both a specification
  # and the gem data to the RemoteFetcher so the built gem can be downloaded.
  #
  # If only the a-3 gem is supposed to be downloaded you can save setup
  # time by creating only specs for the other versions:
  #
  #   spec_fetcher do |fetcher|
  #     fetcher.spec 'a', 1
  #     fetcher.spec 'a', 2, 'b' => 3 # dependency on b = 3
  #     fetcher.gem 'a', 3 do |spec|
  #       # spec is a Gem::Specification
  #       # ...
  #     end
  #   end

  def spec_fetcher(repository = @gem_repo)
    Gem::TestCase::SpecFetcherSetup.declare self, repository do |spec_fetcher_setup|
      yield spec_fetcher_setup if block_given?
    end
  end

  ##
  # Construct a new Gem::Version.

  def v(string)
    Gem::Version.create string
  end

  ##
  # A vendor_gem is used with a gem dependencies file.  The gem created here
  # has no files, just a gem specification for the given +name+ and +version+.
  #
  # Yields the +specification+ to the block, if given

  def vendor_gem(name = 'a', version = 1)
    directory = File.join 'vendor', name

    FileUtils.mkdir_p directory

    save_gemspec name, version, directory
  end

  ##
  # create_gemspec creates gem specification in given +directory+ or '.'
  # for the given +name+ and +version+.
  #
  # Yields the +specification+ to the block, if given

  def save_gemspec(name = 'a', version = 1, directory = '.')
    vendor_spec = Gem::Specification.new name, version do |specification|
      yield specification if block_given?
    end

    File.open File.join(directory, "#{name}.gemspec"), 'w' do |io|
      io.write vendor_spec.to_ruby
    end

    return name, vendor_spec.version, directory
  end

  ##
  # The StaticSet is a static set of gem specifications used for testing only.
  # It is available by requiring Gem::TestCase.

  class StaticSet < Gem::Resolver::Set

    ##
    # A StaticSet ignores remote because it has a fixed set of gems.

    attr_accessor :remote

    ##
    # Creates a new StaticSet for the given +specs+

    def initialize(specs)
      super()

      @specs = specs

      @remote = true
    end

    ##
    # Adds +spec+ to this set.

    def add(spec)
      @specs << spec
    end

    ##
    # Finds +dep+ in this set.

    def find_spec(dep)
      @specs.reverse_each do |s|
        return s if dep.matches_spec? s
      end
    end

    ##
    # Finds all gems matching +dep+ in this set.

    def find_all(dep)
      @specs.find_all { |s| dep.match? s, @prerelease }
    end

    ##
    # Loads a Gem::Specification from this set which has the given +name+,
    # version +ver+, +platform+.  The +source+ is ignored.

    def load_spec(name, ver, platform, source)
      dep = Gem::Dependency.new name, ver
      spec = find_spec dep

      Gem::Specification.new spec.name, spec.version do |s|
        s.platform = spec.platform
      end
    end

    def prefetch(reqs) # :nodoc:
    end

  end

  ##
  # Loads certificate named +cert_name+ from <tt>test/rubygems/</tt>.

  def self.load_cert(cert_name)
    cert_file = cert_path cert_name

    cert = File.read cert_file

    OpenSSL::X509::Certificate.new cert
  end

  ##
  # Returns the path to the certificate named +cert_name+ from
  # <tt>test/rubygems/</tt>.

  def self.cert_path(cert_name)
    if 32 == (Time.at(2**32) rescue 32)
      cert_file = "#{TEST_PATH}/#{cert_name}_cert_32.pem"

      return cert_file if File.exist? cert_file
    end

    "#{TEST_PATH}/#{cert_name}_cert.pem"
  end

  ##
  # Loads an RSA private key named +key_name+ with +passphrase+ in <tt>test/rubygems/</tt>

  def self.load_key(key_name, passphrase = nil)
    key_file = key_path key_name

    key = File.read key_file

    OpenSSL::PKey::RSA.new key, passphrase
  end

  ##
  # Returns the path to the key named +key_name+ from <tt>test/rubygems</tt>

  def self.key_path(key_name)
    "#{TEST_PATH}/#{key_name}_key.pem"
  end

  # :stopdoc:
  # only available in RubyGems tests

  PRIVATE_KEY_PASSPHRASE = 'Foo bar'.freeze

  begin
    PRIVATE_KEY                 = load_key 'private'
    PRIVATE_KEY_PATH            = key_path 'private'

    # ENCRYPTED_PRIVATE_KEY is PRIVATE_KEY encrypted with PRIVATE_KEY_PASSPHRASE
    ENCRYPTED_PRIVATE_KEY       = load_key 'encrypted_private', PRIVATE_KEY_PASSPHRASE
    ENCRYPTED_PRIVATE_KEY_PATH  = key_path 'encrypted_private'

    PUBLIC_KEY                  = PRIVATE_KEY.public_key

    PUBLIC_CERT                 = load_cert 'public'
    PUBLIC_CERT_PATH            = cert_path 'public'
  rescue Errno::ENOENT
    PRIVATE_KEY = nil
    PUBLIC_KEY  = nil
    PUBLIC_CERT = nil
  end if defined?(OpenSSL::SSL)

end

# require dependencies that are not discoverable once GEM_HOME and GEM_PATH
# are wiped
begin
  gem 'rake'
rescue Gem::LoadError
end

begin
  require 'rake/packagetask'
rescue LoadError
end

begin
  gem 'rdoc'
  require 'rdoc'

  require 'rubygems/rdoc'
rescue LoadError, Gem::LoadError
end

begin
  gem 'builder'
  require 'builder/xchar'
rescue LoadError, Gem::LoadError
end

require 'rubygems/test_utilities'
