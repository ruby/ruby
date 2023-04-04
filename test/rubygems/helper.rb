# frozen_string_literal: true

require "rubygems"

begin
  gem "test-unit", "~> 3.0"
rescue Gem::LoadError
end

require "test/unit"

ENV["JARS_SKIP"] = "true" if Gem.java_platform? # avoid unnecessary and noisy `jar-dependencies` post install hook

require "rubygems/deprecate"

require "fileutils"
require "pathname"
require "pp"
require "rubygems/package"
require "shellwords"
require "tmpdir"
require "uri"
require "zlib"
require "benchmark" # stdlib
require "rubygems/mock_gem_ui"

module Gem
  ##
  # Allows setting the gem path searcher.

  def self.searcher=(searcher)
    @searcher = searcher
  end

  ##
  # Allows toggling Windows behavior.

  def self.win_platform=(val)
    @@win_platform = val
  end

  ##
  # Allows setting path to Ruby.

  def self.ruby=(ruby)
    @ruby = ruby
  end

  ##
  # Sets the default user interaction to a MockGemUi.

  module DefaultUserInteraction
    @ui = Gem::MockGemUi.new
  end
end

require "rubygems/command"

class Gem::Command
  ##
  # Allows resetting the hash of specific args per command.

  def self.specific_extra_args_hash=(value)
    @specific_extra_args_hash = value
  end
end

##
# RubyGemTestCase provides a variety of methods for testing rubygems and
# gem-related behavior in a sandbox.  Through RubyGemTestCase you can install
# and uninstall gems, fetch remote gems through a stub fetcher and be assured
# your normal set of gems is not affected.

class Gem::TestCase < Test::Unit::TestCase
  extend Gem::Deprecate

  attr_accessor :fetcher # :nodoc:

  attr_accessor :gem_repo # :nodoc:

  attr_accessor :uri # :nodoc:

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

  def assert_directory_exists(path, msg = nil)
    msg = build_message(msg, "Expected path '#{path}' to be a directory")
    assert_path_exist path
    assert File.directory?(path), msg
  end

  def refute_directory_exists(path, msg = nil)
    msg = build_message(msg, "Expected path '#{path}' not to be a directory")
    assert_path_not_exist path
    refute File.directory?(path), msg
  end

  # https://github.com/seattlerb/minitest/blob/21d9e804b63c619f602f3f4ece6c71b48974707a/lib/minitest/assertions.rb#L188
  def _synchronize
    yield
  end

  # https://github.com/seattlerb/minitest/blob/21d9e804b63c619f602f3f4ece6c71b48974707a/lib/minitest/assertions.rb#L546
  def capture_subprocess_io
    _synchronize do
      require "tempfile"

      captured_stdout = Tempfile.new("out")
      captured_stderr = Tempfile.new("err")

      orig_stdout = $stdout.dup
      orig_stderr = $stderr.dup
      $stdout.reopen captured_stdout
      $stderr.reopen captured_stderr

      yield

      $stdout.rewind
      $stderr.rewind

      return captured_stdout.read, captured_stderr.read
    ensure
      $stdout.reopen orig_stdout
      $stderr.reopen orig_stderr

      orig_stdout.close
      orig_stderr.close
      captured_stdout.close!
      captured_stderr.close!
    end
  end

  ##
  # Sets the ENABLE_SHARED entry in RbConfig::CONFIG to +value+ and restores
  # the original value when the block ends

  def enable_shared(value)
    enable_shared = RbConfig::CONFIG["ENABLE_SHARED"]
    RbConfig::CONFIG["ENABLE_SHARED"] = value

    yield
  ensure
    if enable_shared
      RbConfig::CONFIG["ENABLE_SHARED"] = enable_shared
    else
      RbConfig::CONFIG.delete "ENABLE_SHARED"
    end
  end

  ##
  # Sets the vendordir entry in RbConfig::CONFIG to +value+ and restores the
  # original value when the block ends
  #
  def vendordir(value)
    vendordir = RbConfig::CONFIG["vendordir"]

    if value
      RbConfig::CONFIG["vendordir"] = value
    else
      RbConfig::CONFIG.delete "vendordir"
    end

    yield
  ensure
    if vendordir
      RbConfig::CONFIG["vendordir"] = vendordir
    else
      RbConfig::CONFIG.delete "vendordir"
    end
  end

  ##
  # Sets the bindir entry in RbConfig::CONFIG to +value+ and restores the
  # original value when the block ends
  #
  def bindir(value)
    with_clean_path_to_ruby do
      bindir = RbConfig::CONFIG["bindir"]

      if value
        RbConfig::CONFIG["bindir"] = value
      else
        RbConfig::CONFIG.delete "bindir"
      end

      begin
        yield
      ensure
        if bindir
          RbConfig::CONFIG["bindir"] = bindir
        else
          RbConfig::CONFIG.delete "bindir"
        end
      end
    end
  end

  ##
  # Sets the EXEEXT entry in RbConfig::CONFIG to +value+ and restores the
  # original value when the block ends
  #
  def exeext(value)
    exeext = RbConfig::CONFIG["EXEEXT"]

    if value
      RbConfig::CONFIG["EXEEXT"] = value
    else
      RbConfig::CONFIG.delete "EXEEXT"
    end

    yield
  ensure
    if exeext
      RbConfig::CONFIG["EXEEXT"] = exeext
    else
      RbConfig::CONFIG.delete "EXEEXT"
    end
  end

  def scan_make_command_lines(output)
    output.scan(/^#{Regexp.escape make_command}(?:[[:blank:]].*)?$/)
  end

  def parse_make_command_line_targets(line)
    args = line.sub(/^#{Regexp.escape make_command}/, "").shellsplit

    targets = []

    args.each do |arg|
      case arg
      when /\A(\w+)=/
      else
        targets << arg
      end
    end

    targets << "" if targets.empty?

    targets
  end

  def assert_contains_make_command(target, output, msg = nil)
    if output.include?("\n")
      msg = build_message(msg,
        "Expected output containing make command \"%s\", but was \n\nBEGIN_OF_OUTPUT\n%sEND_OF_OUTPUT" % [
          ("%s %s" % [make_command, target]).rstrip,
          output,
        ])
    else
      msg = build_message(msg,
        'Expected make command "%s", but was "%s"' % [
          ("%s %s" % [make_command, target]).rstrip,
          output,
        ])
    end

    assert scan_make_command_lines(output).any? {|line|
      targets = parse_make_command_line_targets(line)

      if targets.include?(target)
        true
      else
        false
      end
    }, msg
  end

  include Gem::DefaultUserInteraction

  ##
  # #setup prepares a sandboxed location to install gems.  All installs are
  # directed to a temporary directory.  All install plugins are removed.
  #
  # If the +RUBY+ environment variable is set the given path is used for
  # Gem::ruby.  The local platform is set to <tt>i386-mswin32</tt> for Windows
  # or <tt>i686-darwin8.10.1</tt> otherwise.

  def setup
    @orig_hooks = {}
    @orig_env = ENV.to_hash
    @tmp = File.expand_path("tmp")

    FileUtils.mkdir_p @tmp

    @tempdir = Dir.mktmpdir("test_rubygems_", @tmp)
    @tempdir.tap(&Gem::UNTAINT)

    ENV["GEM_VENDOR"] = nil
    ENV["GEMRC"] = nil
    ENV["XDG_CACHE_HOME"] = nil
    ENV["XDG_CONFIG_HOME"] = nil
    ENV["XDG_DATA_HOME"] = nil
    ENV["XDG_STATE_HOME"] = nil
    ENV["SOURCE_DATE_EPOCH"] = nil
    ENV["BUNDLER_VERSION"] = nil
    ENV["RUBYGEMS_PREVENT_UPDATE_SUGGESTION"] = "true"

    @current_dir = Dir.pwd
    @fetcher     = nil

    @back_ui                       = Gem::DefaultUserInteraction.ui
    @ui                            = Gem::MockGemUi.new
    # This needs to be a new instance since we call use_ui(@ui) when we want to
    # capture output
    Gem::DefaultUserInteraction.ui = Gem::MockGemUi.new

    @orig_SYSTEM_WIDE_CONFIG_FILE = Gem::ConfigFile::SYSTEM_WIDE_CONFIG_FILE
    Gem::ConfigFile.send :remove_const, :SYSTEM_WIDE_CONFIG_FILE
    Gem::ConfigFile.send :const_set, :SYSTEM_WIDE_CONFIG_FILE,
                         File.join(@tempdir, "system-gemrc")

    @gemhome  = File.join @tempdir, "gemhome"
    @userhome = File.join @tempdir, "userhome"
    @statehome = File.join @tempdir, "statehome"
    ENV["GEM_SPEC_CACHE"] = File.join @tempdir, "spec_cache"

    @orig_ruby = if ENV["RUBY"]
      ruby = Gem.ruby
      Gem.ruby = ENV["RUBY"]
      ruby
    end

    @git = ENV["GIT"] || "git#{RbConfig::CONFIG["EXEEXT"]}"

    Gem.ensure_gem_subdirectories @gemhome
    Gem.ensure_default_gem_subdirectories @gemhome

    @orig_LOAD_PATH = $LOAD_PATH.dup
    $LOAD_PATH.map! do |s|
      expand_path = begin
                      File.realpath(s)
                    rescue StandardError
                      File.expand_path(s)
                    end
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

    ENV["HOME"] = @userhome
    Gem.instance_variable_set :@config_file, nil
    Gem.instance_variable_set :@user_home, nil
    Gem.instance_variable_set :@config_home, nil
    Gem.instance_variable_set :@data_home, nil
    Gem.instance_variable_set :@state_home, @statehome
    Gem.instance_variable_set :@gemdeps, nil
    Gem.instance_variable_set :@env_requirements_by_name, nil
    Gem.send :remove_instance_variable, :@ruby_version if
      Gem.instance_variables.include? :@ruby_version

    FileUtils.mkdir_p @userhome

    ENV["GEM_PRIVATE_KEY_PASSPHRASE"] = PRIVATE_KEY_PASSPHRASE

    Gem.instance_variable_set(:@default_specifications_dir, nil)
    if Gem.java_platform?
      @orig_default_gem_home = RbConfig::CONFIG["default_gem_home"]
      RbConfig::CONFIG["default_gem_home"] = @gemhome
    else
      Gem.instance_variable_set(:@default_dir, @gemhome)
    end

    @orig_bindir = RbConfig::CONFIG["bindir"]
    RbConfig::CONFIG["bindir"] = File.join @gemhome, "bin"

    @orig_sitelibdir = RbConfig::CONFIG["sitelibdir"]
    new_sitelibdir = @orig_sitelibdir.sub(RbConfig::CONFIG["prefix"], @gemhome)
    $LOAD_PATH.insert(Gem.load_path_insert_index, new_sitelibdir)
    RbConfig::CONFIG["sitelibdir"] = new_sitelibdir

    @orig_mandir = RbConfig::CONFIG["mandir"]
    RbConfig::CONFIG["mandir"] = File.join @gemhome, "share", "man"

    Gem::Specification.unresolved_deps.clear
    Gem.use_paths(@gemhome)

    Gem.loaded_specs.clear
    Gem.instance_variable_set(:@activated_gem_paths, 0)
    Gem.clear_default_specs

    Gem.configuration.verbose = true
    Gem.configuration.update_sources = true

    Gem::RemoteFetcher.fetcher = Gem::FakeFetcher.new

    @gem_repo = "http://gems.example.com/"
    @uri = URI.parse @gem_repo
    Gem.sources.replace [@gem_repo]

    Gem.searcher = nil
    Gem::SpecFetcher.fetcher = nil

    @orig_arch = RbConfig::CONFIG["arch"]

    if win_platform?
      util_set_arch "i386-mswin32"
    else
      util_set_arch "i686-darwin8.10.1"
    end

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
        ($LOADED_FEATURES - @orig_LOADED_FEATURES).each do |feat|
          $LOADED_FEATURES.delete(feat) if feat.start_with?(@tmp)
        end
      else
        $LOADED_FEATURES.replace @orig_LOADED_FEATURES
      end
    end

    RbConfig::CONFIG["arch"] = @orig_arch

    if defined? Gem::RemoteFetcher
      Gem::RemoteFetcher.fetcher = nil
    end

    Dir.chdir @current_dir

    FileUtils.rm_rf @tempdir

    restore_env

    Gem::ConfigFile.send :remove_const, :SYSTEM_WIDE_CONFIG_FILE
    Gem::ConfigFile.send :const_set, :SYSTEM_WIDE_CONFIG_FILE,
                         @orig_SYSTEM_WIDE_CONFIG_FILE

    Gem.ruby = @orig_ruby if @orig_ruby

    RbConfig::CONFIG["mandir"] = @orig_mandir
    RbConfig::CONFIG["sitelibdir"] = @orig_sitelibdir
    RbConfig::CONFIG["bindir"] = @orig_bindir

    Gem.instance_variable_set :@default_specifications_dir, nil
    if Gem.java_platform?
      RbConfig::CONFIG["default_gem_home"] = @orig_default_gem_home
    else
      Gem.instance_variable_set :@default_dir, nil
    end

    Gem::Specification.unresolved_deps.clear
    Gem.refresh

    @orig_hooks.each do |name, hooks|
      Gem.send(name).replace hooks
    end

    @back_ui.close
  end

  def credential_setup
    @temp_cred = File.join(@userhome, ".gem", "credentials")
    FileUtils.mkdir_p File.dirname(@temp_cred)
    File.write @temp_cred, ":rubygems_api_key: 701229f217cdf23b1344c7b4b54ca97"
    File.chmod 0600, @temp_cred
  end

  def credential_teardown
    FileUtils.rm_rf @temp_cred
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

  def without_any_upwards_gemfiles
    ENV["BUNDLE_GEMFILE"] = File.join(@tempdir, "Gemfile")
  end

  ##
  # A git_gem is used with a gem dependencies file.  The gem created here
  # has no files, just a gem specification for the given +name+ and +version+.
  #
  # Yields the +specification+ to the block, if given

  def git_gem(name = "a", version = 1)
    have_git?

    directory = File.join "git", name
    directory = File.expand_path directory

    git_spec = Gem::Specification.new name, version do |specification|
      yield specification if block_given?
    end

    FileUtils.mkdir_p directory

    gemspec = "#{name}.gemspec"

    File.open File.join(directory, gemspec), "w" do |io|
      io.write git_spec.to_ruby
    end

    head = nil

    Dir.chdir directory do
      unless File.exist? ".git"
        system @git, "init", "--quiet"
        system @git, "config", "user.name",  "RubyGems Tests"
        system @git, "config", "user.email", "rubygems@example"
      end

      system @git, "add", gemspec
      system @git, "commit", "-a", "-m", "a non-empty commit message", "--quiet"
      head = Gem::Util.popen(@git, "rev-parse", "HEAD").strip
    end

    [name, git_spec.version, directory, head]
  end

  ##
  # Skips this test unless you have a git executable

  def have_git?
    return if in_path? @git

    pend "cannot find git executable, use GIT environment variable to set"
  end

  def in_path?(executable) # :nodoc:
    return true if %r{\A([A-Z]:|/)} =~ executable && File.exist?(executable)

    ENV["PATH"].split(File::PATH_SEPARATOR).any? do |directory|
      File.exist? File.join directory, executable
    end
  end

  ##
  # Builds and installs the Gem::Specification +spec+

  def install_gem(spec, options = {})
    require "rubygems/installer"

    gem = spec.cache_file

    unless File.exist? gem
      use_ui Gem::MockGemUi.new do
        Dir.chdir @tempdir do
          Gem::Package.build spec
        end
      end

      gem = File.join(@tempdir, File.basename(gem)).tap(&Gem::UNTAINT)
    end

    Gem::Installer.at(gem, options.merge({ :wrappers => true })).install
  end

  ##
  # Builds and installs the Gem::Specification +spec+ into the user dir

  def install_gem_user(spec)
    install_gem spec, :user_install => true
  end

  ##
  # Uninstalls the Gem::Specification +spec+
  def uninstall_gem(spec)
    require "rubygems/uninstaller"

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
    File.open path.dup.tap(&Gem::UNTAINT), "rb" do |io|
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

    File.open path, "wb" do |io|
      yield io if block_given?
    end

    path
  end

  ##
  # Load a YAML string, the psych 3 way

  def load_yaml(yaml)
    if Psych.respond_to?(:unsafe_load)
      Psych.unsafe_load(yaml)
    else
      Psych.load(yaml)
    end
  end

  ##
  # Load a YAML file, the psych 3 way

  def load_yaml_file(file)
    if Psych.respond_to?(:unsafe_load_file)
      Psych.unsafe_load_file(file)
    else
      Psych.load_file(file)
    end
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

  def quick_gem(name, version="2")
    require "rubygems/specification"

    spec = Gem::Specification.new do |s|
      s.platform    = Gem::Platform::RUBY
      s.name        = name
      s.version     = version
      s.author      = "A User"
      s.email       = "example@example.com"
      s.homepage    = "http://example.com"
      s.summary     = "this is a summary"
      s.description = "This is a test description"

      yield(s) if block_given?
    end

    written_path = write_file spec.spec_file do |io|
      io.write spec.to_ruby_for_cache
    end

    spec.loaded_from = written_path

    Gem::Specification.reset

    spec
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

        File.open file, "w" do |fp|
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
      Gem::Installer.for_spec(spec, :force => true).install
    end

    Gem.searcher = nil
  end

  ##
  # Installs the provided default specs including writing the spec file

  def install_default_gems(*specs)
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

  def new_default_spec(name, version, deps = nil, *files)
    spec = util_spec name, version, deps

    spec.loaded_from = File.join(@gemhome, "specifications", "default", spec.spec_name)
    spec.files = files

    lib_dir = File.join(@tempdir, "default_gems", "lib")
    lib_dir.instance_variable_set(:@gem_prelude_index, lib_dir)
    Gem.instance_variable_set(:@default_gem_load_paths, [*Gem.send(:default_gem_load_paths), lib_dir])
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
    raise "deps or block, not both" if deps && block_given?

    spec = Gem::Specification.new do |s|
      s.platform    = Gem::Platform::RUBY
      s.name        = name
      s.version     = version
      s.author      = "A User"
      s.email       = "example@example.com"
      s.homepage    = "http://example.com"
      s.summary     = "this is a summary"
      s.description = "This is a test description"

      s.files.push(*files) unless files.empty?

      yield s if block_given?
    end

    if deps
      deps.keys.each do |n|
        spec.add_dependency n, (deps[n] || ">= 0")
      end
    end

    unless files.empty?
      write_file spec.spec_file do |io|
        io.write spec.to_ruby_for_cache
      end

      util_build_gem spec

      FileUtils.rm spec.spec_file
    end

    spec
  end

  ##
  # Creates a gem with +name+, +version+ and +deps+.  The specification will
  # be yielded before gem creation for customization.  The gem will be placed
  # in <tt>File.join @tempdir, 'gems'</tt>.  The specification and .gem file
  # location are returned.

  def util_gem(name, version, deps = nil, &block)
    if deps
      block = proc do |s|
        deps.keys.each do |n|
          s.add_dependency n, (deps[n] || ">= 0")
        end
      end
    end

    spec = quick_gem(name, version, &block)

    util_build_gem spec

    cache_file = File.join @tempdir, "gems", "#{spec.original_name}.gem"
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
    @a1 = quick_gem "a", "1" do |s|
      s.files = %w[lib/code.rb]
      s.require_paths = %w[lib]
      s.date = Gem::Specification::TODAY - 86_400
      s.homepage = "http://a.example.com"
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

    @a2      = quick_gem("a", "2",      &init)
    @a3a     = quick_gem("a", "3.a",    &init)
    @a_evil9 = quick_gem("a_evil", "9", &init)
    @b2      = quick_gem("b", "2",      &init)
    @c1_2    = quick_gem("c", "1.2",    &init)
    @x       = quick_gem("x", "1",      &init)
    @dep_x   = quick_gem("dep_x", "1") do |s|
      s.files = %w[lib/code.rb]
      s.require_paths = %w[lib]
      s.add_dependency "x", ">= 1"
    end

    @pl1 = quick_gem "pl", "1" do |s| # l for legacy
      s.files = %w[lib/code.rb]
      s.require_paths = %w[lib]
      s.platform = Gem::Platform.new "i386-linux"
      s.instance_variable_set :@original_platform, "i386-linux"
    end

    if prerelease
      @a2_pre = quick_gem("a", "2.a", &init)
      write_file File.join(*%W[gems #{@a2_pre.original_name} lib code.rb])
      util_build_gem @a2_pre
    end

    write_file File.join(*%W[gems #{@a1.original_name} lib code.rb])
    write_file File.join(*%W[gems #{@a2.original_name} lib code.rb])
    write_file File.join(*%W[gems #{@a3a.original_name} lib code.rb])
    write_file File.join(*%W[gems #{@a_evil9.original_name} lib code.rb])
    write_file File.join(*%W[gems #{@b2.original_name} lib code.rb])
    write_file File.join(*%W[gems #{@c1_2.original_name} lib code.rb])
    write_file File.join(*%W[gems #{@pl1.original_name} lib code.rb])
    write_file File.join(*%W[gems #{@x.original_name} lib code.rb])
    write_file File.join(*%W[gems #{@dep_x.original_name} lib code.rb])

    [@a1, @a2, @a3a, @a_evil9, @b2, @c1_2, @pl1, @x, @dep_x].each do |spec|
      util_build_gem spec
    end

    FileUtils.rm_r File.join(@gemhome, "gems", @pl1.original_name)
  end

  ##
  # Set the platform to +arch+

  def util_set_arch(arch)
    RbConfig::CONFIG["arch"] = arch
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

    prerelease, all = all_specs.partition {|spec| spec.version.prerelease? }
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

    # HACK: for test_download_to_cache
    unless Gem::RemoteFetcher === @fetcher
      v = Gem.marshal_version

      specs = all.map(&:name_tuple)
      s_zip = util_gzip Marshal.dump Gem::NameTuple.to_basic specs

      latest_specs = latest.map(&:name_tuple)

      l_zip = util_gzip Marshal.dump Gem::NameTuple.to_basic latest_specs

      prerelease_specs = prerelease.map(&:name_tuple)
      p_zip = util_gzip Marshal.dump Gem::NameTuple.to_basic prerelease_specs

      @fetcher.data["#{@gem_repo}specs.#{v}.gz"]            = s_zip
      @fetcher.data["#{@gem_repo}latest_specs.#{v}.gz"]     = l_zip
      @fetcher.data["#{@gem_repo}prerelease_specs.#{v}.gz"] = p_zip

      write_marshalled_gemspecs(*all_specs)
    end

    nil # force errors
  end

  def write_marshalled_gemspecs(*all_specs)
    v = Gem.marshal_version

    all_specs.each do |spec|
      path = "#{@gem_repo}quick/Marshal.#{v}/#{spec.original_name}.gemspec.rz"
      data = Marshal.dump spec
      data_deflate = Zlib::Deflate.deflate data
      @fetcher.data[path] = data_deflate
    end
  end

  ##
  # Deflates +data+

  def util_zip(data)
    Zlib::Deflate.deflate data
  end

  def util_set_RUBY_VERSION(version, patchlevel, revision, description, engine = "ruby", engine_version = nil)
    if Gem.instance_variables.include? :@ruby_version
      Gem.send :remove_instance_variable, :@ruby_version
    end

    @RUBY_VERSION        = RUBY_VERSION
    @RUBY_PATCHLEVEL     = RUBY_PATCHLEVEL
    @RUBY_REVISION       = RUBY_REVISION
    @RUBY_DESCRIPTION    = RUBY_DESCRIPTION
    @RUBY_ENGINE         = RUBY_ENGINE
    @RUBY_ENGINE_VERSION = RUBY_ENGINE_VERSION

    util_clear_RUBY_VERSION

    Object.const_set :RUBY_VERSION,        version
    Object.const_set :RUBY_PATCHLEVEL,     patchlevel
    Object.const_set :RUBY_REVISION,       revision
    Object.const_set :RUBY_DESCRIPTION,    description
    Object.const_set :RUBY_ENGINE,         engine
    Object.const_set :RUBY_ENGINE_VERSION, engine_version
  end

  def util_restore_RUBY_VERSION
    util_clear_RUBY_VERSION

    Object.const_set :RUBY_VERSION,        @RUBY_VERSION
    Object.const_set :RUBY_PATCHLEVEL,     @RUBY_PATCHLEVEL
    Object.const_set :RUBY_REVISION,       @RUBY_REVISION
    Object.const_set :RUBY_DESCRIPTION,    @RUBY_DESCRIPTION
    Object.const_set :RUBY_ENGINE,         @RUBY_ENGINE
    Object.const_set :RUBY_ENGINE_VERSION, @RUBY_ENGINE_VERSION
  end

  def util_clear_RUBY_VERSION
    Object.send :remove_const, :RUBY_VERSION
    Object.send :remove_const, :RUBY_PATCHLEVEL
    Object.send :remove_const, :RUBY_REVISION
    Object.send :remove_const, :RUBY_DESCRIPTION
    Object.send :remove_const, :RUBY_ENGINE
    Object.send :remove_const, :RUBY_ENGINE_VERSION
  end

  ##
  # Is this test being run on a Windows platform?

  def self.win_platform?
    Gem.win_platform?
  end

  ##
  # see ::win_platform?

  def win_platform?
    self.class.win_platform?
  end

  ##
  # Is this test being run on a Java platform?

  def self.java_platform?
    Gem.java_platform?
  end

  ##
  # see ::java_platform?

  def java_platform?
    self.class.java_platform?
  end

  ##
  # Returns whether or not we're on a version of Ruby built with VC++ (or
  # Borland) versus Cygwin, Mingw, etc.

  def self.vc_windows?
    RUBY_PLATFORM.match("mswin")
  end

  ##
  # see ::vc_windows?

  def vc_windows?
    self.class.vc_windows?
  end

  ##
  # Is this test being run on a version of Ruby built with mingw?

  def self.mingw_windows?
    RUBY_PLATFORM.match("mingw")
  end

  ##
  # see ::mingw_windows?

  def mingw_windows?
    self.class.mingw_windows?
  end

  ##
  # Is this test being run on a ruby/ruby repository?
  #

  def ruby_repo?
    !ENV["GEM_COMMAND"].nil?
  end

  ##
  # Returns the make command for the current platform. For versions of Ruby
  # built on MS Windows with VC++ or Borland it will return 'nmake'. On all
  # other platforms, including Cygwin, it will return 'make'.

  def self.make_command
    ENV["make"] || ENV["MAKE"] || (vc_windows? ? "nmake" : "make")
  end

  ##
  # See ::make_command

  def make_command
    self.class.make_command
  end

  ##
  # Returns whether or not the nmake command could be found.

  def nmake_found?
    system("nmake /? 1>NUL 2>&1")
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
    Gem.ruby = self.class.rubybin
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
    rubyexe = "#{ruby}#{RbConfig::CONFIG["EXEEXT"]}"

    3.times do
      if File.exist?(ruby) && File.executable?(ruby) && !File.directory?(ruby)
        return File.expand_path(ruby)
      end
      if File.exist?(rubyexe) && File.executable?(rubyexe)
        return File.expand_path(rubyexe)
      end
      ruby = File.join("..", ruby)
    end

    begin
      Gem.ruby
    rescue LoadError
      "ruby"
    end
  end

  def ruby_with_rubygems_in_load_path
    [Gem.ruby, "-I", rubygems_path]
  end

  def rubygems_path
    $LOAD_PATH.find {|p| p == File.dirname($LOADED_FEATURES.find {|f| f.end_with?("/rubygems.rb") }) }
  end

  def bundler_path
    $LOAD_PATH.find {|p| p == File.dirname($LOADED_FEATURES.find {|f| f.end_with?("/bundler.rb") }) }
  end

  def with_clean_path_to_ruby
    orig_ruby = Gem.ruby

    Gem.instance_variable_set :@ruby, nil

    yield
  ensure
    Gem.instance_variable_set :@ruby, orig_ruby
  end

  def with_internal_encoding(encoding)
    int_enc = Encoding.default_internal
    silence_warnings { Encoding.default_internal = encoding }

    yield
  ensure
    silence_warnings { Encoding.default_internal = int_enc }
  end

  def silence_warnings
    old_verbose = $VERBOSE
    $VERBOSE = false
    yield
  ensure
    $VERBOSE = old_verbose
  end

  class << self
    # :nodoc:
    ##
    # Return the join path, with escaping backticks, dollars, and
    # double-quotes.  Unlike `shellescape`, equal-sign is not escaped.

    private

    def escape_path(*path)
      path = File.join(*path)
      if %r{\A[-+:/=@,.\w]+\z} =~ path
        path
      else
        "\"#{path.gsub(/[`$"]/, '\\&')}\""
      end
    end
  end

  @@good_rake = "#{rubybin} #{escape_path(__dir__, "good_rake.rb")}"
  @@bad_rake = "#{rubybin} #{escape_path(__dir__, "bad_rake.rb")}"

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

  def vendor_gem(name = "a", version = 1)
    directory = File.join "vendor", name

    FileUtils.mkdir_p directory

    save_gemspec name, version, directory
  end

  ##
  # create_gemspec creates gem specification in given +directory+ or '.'
  # for the given +name+ and +version+.
  #
  # Yields the +specification+ to the block, if given

  def save_gemspec(name = "a", version = 1, directory = ".")
    vendor_spec = Gem::Specification.new name, version do |specification|
      yield specification if block_given?
    end

    File.open File.join(directory, "#{name}.gemspec"), "w" do |io|
      io.write vendor_spec.to_ruby
    end

    [name, vendor_spec.version, directory]
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
      @specs.find_all {|s| dep.match? s, @prerelease }
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
    if begin
         Time.at(2**32)
       rescue StandardError
         32
       end == 32
      cert_file = "#{__dir__}/#{cert_name}_cert_32.pem"

      return cert_file if File.exist? cert_file
    end

    "#{__dir__}/#{cert_name}_cert.pem"
  end

  ##
  # Loads a private key named +key_name+ with +passphrase+ in <tt>test/rubygems/</tt>

  def self.load_key(key_name, passphrase = nil)
    key_file = key_path key_name

    key = File.read key_file

    OpenSSL::PKey.read key, passphrase
  end

  ##
  # Returns the path to the key named +key_name+ from <tt>test/rubygems</tt>

  def self.key_path(key_name)
    "#{__dir__}/#{key_name}_key.pem"
  end

  # :stopdoc:
  # only available in RubyGems tests

  PRIVATE_KEY_PASSPHRASE = "Foo bar"

  begin
    PRIVATE_KEY                 = load_key "private"
    PRIVATE_KEY_PATH            = key_path "private"

    # ENCRYPTED_PRIVATE_KEY is PRIVATE_KEY encrypted with PRIVATE_KEY_PASSPHRASE
    ENCRYPTED_PRIVATE_KEY       = load_key "encrypted_private", PRIVATE_KEY_PASSPHRASE
    ENCRYPTED_PRIVATE_KEY_PATH  = key_path "encrypted_private"

    PUBLIC_KEY                  = PRIVATE_KEY.public_key

    PUBLIC_CERT                 = load_cert "public"
    PUBLIC_CERT_PATH            = cert_path "public"
  rescue Errno::ENOENT
    PRIVATE_KEY = nil
    PUBLIC_KEY  = nil
    PUBLIC_CERT = nil
  end if Gem::HAVE_OPENSSL

  private

  def restore_env
    unless Gem.win_platform?
      ENV.replace(@orig_env)
      return
    end

    # Fallback logic for Windows below to workaround
    # https://bugs.ruby-lang.org/issues/16798. Can be dropped once all
    # supported rubies include the fix for that.

    ENV.clear

    @orig_env.each {|k, v| ENV[k] = v }
  end
end

# https://github.com/seattlerb/minitest/blob/13c48a03d84a2a87855a4de0c959f96800100357/lib/minitest/mock.rb#L192
class Object
  def stub(name, val_or_callable, *block_args)
    new_name = "__minitest_stub__#{name}"

    metaclass = class << self; self; end

    if respond_to?(name) && !methods.map(&:to_s).include?(name.to_s)
      metaclass.send :define_method, name do |*args|
        super(*args)
      end
    end

    metaclass.send :alias_method, new_name, name

    metaclass.send :define_method, name do |*args, &blk|
      if val_or_callable.respond_to? :call
        val_or_callable.call(*args, &blk)
      else
        blk&.call(*block_args)
        val_or_callable
      end
    end

    metaclass.send(:ruby2_keywords, name) if metaclass.respond_to?(:ruby2_keywords, true)

    yield self
  ensure
    metaclass.send :undef_method, name
    metaclass.send :alias_method, name, new_name
    metaclass.send :undef_method, new_name
  end unless method_defined?(:stub) # lib/resolv/test_dns.rb also has the same method definition
end

require_relative "utilities"
