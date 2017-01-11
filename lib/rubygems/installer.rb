# frozen_string_literal: true
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems/command'
require 'rubygems/exceptions'
require 'rubygems/package'
require 'rubygems/ext'
require 'rubygems/user_interaction'
require 'fileutils'

##
# The installer installs the files contained in the .gem into the Gem.home.
#
# Gem::Installer does the work of putting files in all the right places on the
# filesystem including unpacking the gem into its gem dir, installing the
# gemspec in the specifications dir, storing the cached gem in the cache dir,
# and installing either wrappers or symlinks for executables.
#
# The installer invokes pre and post install hooks.  Hooks can be added either
# through a rubygems_plugin.rb file in an installed gem or via a
# rubygems/defaults/#{RUBY_ENGINE}.rb or rubygems/defaults/operating_system.rb
# file.  See Gem.pre_install and Gem.post_install for details.

class Gem::Installer

  ##
  # Paths where env(1) might live.  Some systems are broken and have it in
  # /bin

  ENV_PATHS = %w[/usr/bin/env /bin/env]

  ##
  # Deprecated in favor of Gem::Ext::BuildError

  ExtensionBuildError = Gem::Ext::BuildError # :nodoc:

  include Gem::UserInteraction

  ##
  # Filename of the gem being installed.

  attr_reader :gem

  ##
  # The directory a gem's executables will be installed into

  attr_reader :bin_dir

  attr_reader :build_root # :nodoc:

  ##
  # The gem repository the gem will be installed into

  attr_reader :gem_home

  ##
  # The options passed when the Gem::Installer was instantiated.

  attr_reader :options

  @path_warning = false

  @install_lock = Mutex.new

  class << self

    ##
    # True if we've warned about PATH not including Gem.bindir

    attr_accessor :path_warning

    ##
    # Certain aspects of the install process are not thread-safe. This lock is
    # used to allow multiple threads to install Gems at the same time.

    attr_reader :install_lock

    ##
    # Overrides the executable format.
    #
    # This is a sprintf format with a "%s" which will be replaced with the
    # executable name.  It is based off the ruby executable name's difference
    # from "ruby".

    attr_writer :exec_format

    # Defaults to use Ruby's program prefix and suffix.
    def exec_format
      @exec_format ||= Gem.default_exec_format
    end

  end

  ##
  # Construct an installer object for the gem file located at +path+

  def self.at path, options = {}
    security_policy = options[:security_policy]
    package = Gem::Package.new path, security_policy
    new package, options
  end

  class FakePackage
    attr_accessor :spec

    def initialize(spec)
      @spec = spec
    end

    def extract_files destination_dir, pattern = '*'
      FileUtils.mkdir_p destination_dir

      spec.files.each do |file|
        file = File.join destination_dir, file
        next if File.exist? file
        FileUtils.mkdir_p File.dirname(file)
        File.open file, 'w' do |fp| fp.puts "# #{file}" end
      end
    end

    def copy_to path
    end
  end

  ##
  # Construct an installer object for an ephemeral gem (one where we don't
  # actually have a .gem file, just a spec)

  def self.for_spec spec, options = {}
    # FIXME: we should have a real Package class for this
    new FakePackage.new(spec), options
  end

  ##
  # Constructs an Installer instance that will install the gem located at
  # +gem+.  +options+ is a Hash with the following keys:
  #
  # :bin_dir:: Where to put a bin wrapper if needed.
  # :development:: Whether or not development dependencies should be installed.
  # :env_shebang:: Use /usr/bin/env in bin wrappers.
  # :force:: Overrides all version checks and security policy checks, except
  #          for a signed-gems-only policy.
  # :format_executable:: Format the executable the same as the Ruby executable.
  #                      If your Ruby is ruby18, foo_exec will be installed as
  #                      foo_exec18.
  # :ignore_dependencies:: Don't raise if a dependency is missing.
  # :install_dir:: The directory to install the gem into.
  # :security_policy:: Use the specified security policy.  See Gem::Security
  # :user_install:: Indicate that the gem should be unpacked into the users
  #                 personal gem directory.
  # :only_install_dir:: Only validate dependencies against what is in the
  #                     install_dir
  # :wrappers:: Install wrappers if true, symlinks if false.
  # :build_args:: An Array of arguments to pass to the extension builder
  #               process. If not set, then Gem::Command.build_args is used

  def initialize(package, options={})
    require 'fileutils'

    @options = options
    if package.is_a? String
      security_policy = options[:security_policy]
      @package = Gem::Package.new package, security_policy
      if $VERBOSE
        warn "constructing an Installer object with a string is deprecated. Please use Gem::Installer.at (called from: #{caller.first})"
      end
    else
      @package = package
    end

    process_options

    if options[:user_install] and not options[:unpack] then
      @gem_home = Gem.user_dir
      @bin_dir = Gem.bindir gem_home unless options[:bin_dir]
      check_that_user_bin_dir_is_in_path
    end
  end

  ##
  # Checks if +filename+ exists in +@bin_dir+.
  #
  # If +@force+ is set +filename+ is overwritten.
  #
  # If +filename+ exists and is a RubyGems wrapper for different gem the user
  # is consulted.
  #
  # If +filename+ exists and +@bin_dir+ is Gem.default_bindir (/usr/local) the
  # user is consulted.
  #
  # Otherwise +filename+ is overwritten.

  def check_executable_overwrite filename # :nodoc:
    return if @force

    generated_bin = File.join @bin_dir, formatted_program_filename(filename)

    return unless File.exist? generated_bin

    ruby_executable = false
    existing = nil

    open generated_bin, 'rb' do |io|
      next unless io.gets =~ /^#!/ # shebang
      io.gets # blankline

      # TODO detect a specially formatted comment instead of trying
      # to run a regexp against Ruby code.
      next unless io.gets =~ /This file was generated by RubyGems/

      ruby_executable = true
      existing = io.read.slice(%r{
          ^(
            gem \s |
            load \s Gem\.bin_path\( |
            load \s Gem\.activate_bin_path\(
          )
          (['"])(.*?)(\2),
        }x, 3)
    end

    return if spec.name == existing

    # somebody has written to RubyGems' directory, overwrite, too bad
    return if Gem.default_bindir != @bin_dir and not ruby_executable

    question = "#{spec.name}'s executable \"#{filename}\" conflicts with ".dup

    if ruby_executable then
      question << (existing || 'an unknown executable')

      return if ask_yes_no "#{question}\nOverwrite the executable?", false

      conflict = "installed executable from #{existing}"
    else
      question << generated_bin

      return if ask_yes_no "#{question}\nOverwrite the executable?", false

      conflict = generated_bin
    end

    raise Gem::InstallError,
      "\"#{filename}\" from #{spec.name} conflicts with #{conflict}"
  end

  ##
  # Lazy accessor for the spec's gem directory.

  def gem_dir
    @gem_dir ||= File.join(gem_home, "gems", spec.full_name)
  end

  ##
  # Lazy accessor for the installer's spec.

  def spec
    @package.spec
  rescue Gem::Package::Error => e
    raise Gem::InstallError, "invalid gem: #{e.message}"
  end

  ##
  # Installs the gem and returns a loaded Gem::Specification for the installed
  # gem.
  #
  # The gem will be installed with the following structure:
  #
  #   @gem_home/
  #     cache/<gem-version>.gem #=> a cached copy of the installed gem
  #     gems/<gem-version>/... #=> extracted files
  #     specifications/<gem-version>.gemspec #=> the Gem::Specification

  def install
    pre_install_checks

    FileUtils.rm_f File.join gem_home, 'specifications', spec.spec_name

    run_pre_install_hooks

    # Set loaded_from to ensure extension_dir is correct
    if @options[:install_as_default] then
      spec.loaded_from = default_spec_file
    else
      spec.loaded_from = spec_file
    end

    # Completely remove any previous gem files
    FileUtils.rm_rf gem_dir
    FileUtils.rm_rf spec.extension_dir

    FileUtils.mkdir_p gem_dir

    if @options[:install_as_default] then
      extract_bin
      write_default_spec
    else
      extract_files

      build_extensions
      write_build_info_file
      run_post_build_hooks

      generate_bin
      write_spec
      write_cache_file
    end

    say spec.post_install_message if options[:post_install_message] && !spec.post_install_message.nil?

    Gem::Installer.install_lock.synchronize { Gem::Specification.reset }

    run_post_install_hooks

    spec

  # TODO This rescue is in the wrong place. What is raising this exception?
  # move this rescue to around the code that actually might raise it.
  rescue Zlib::GzipFile::Error
    raise Gem::InstallError, "gzip error installing #{gem}"
  end

  def run_pre_install_hooks # :nodoc:
    Gem.pre_install_hooks.each do |hook|
      if hook.call(self) == false then
        location = " at #{$1}" if hook.inspect =~ /@(.*:\d+)/

        message = "pre-install hook#{location} failed for #{spec.full_name}"
        raise Gem::InstallError, message
      end
    end
  end

  def run_post_build_hooks # :nodoc:
    Gem.post_build_hooks.each do |hook|
      if hook.call(self) == false then
        FileUtils.rm_rf gem_dir

        location = " at #{$1}" if hook.inspect =~ /@(.*:\d+)/

        message = "post-build hook#{location} failed for #{spec.full_name}"
        raise Gem::InstallError, message
      end
    end
  end

  def run_post_install_hooks # :nodoc:
    Gem.post_install_hooks.each do |hook|
      hook.call self
    end
  end

  ##
  #
  # Return an Array of Specifications contained within the gem_home
  # we'll be installing into.

  def installed_specs
    @specs ||= begin
      specs = []

      Dir[File.join(gem_home, "specifications", "*.gemspec")].each do |path|
        spec = Gem::Specification.load path.untaint
        specs << spec if spec
      end

      specs
    end
  end

  ##
  # Ensure that the dependency is satisfied by the current installation of
  # gem.  If it is not an exception is raised.
  #
  # spec       :: Gem::Specification
  # dependency :: Gem::Dependency

  def ensure_dependency(spec, dependency)
    unless installation_satisfies_dependency? dependency then
      raise Gem::InstallError, "#{spec.name} requires #{dependency}"
    end
    true
  end

  ##
  # True if the gems in the system satisfy +dependency+.

  def installation_satisfies_dependency?(dependency)
    return true if @options[:development] and dependency.type == :development
    return true if installed_specs.detect { |s| dependency.matches_spec? s }
    return false if @only_install_dir
    not dependency.matching_specs.empty?
  end

  ##
  # Unpacks the gem into the given directory.

  def unpack(directory)
    @gem_dir = directory
    extract_files
  end

  ##
  # The location of the spec file that is installed.
  #

  def spec_file
    File.join gem_home, "specifications", "#{spec.full_name}.gemspec"
  end

  ##
  # The location of the default spec file for default gems.
  #

  def default_spec_file
    File.join Gem::Specification.default_specifications_dir, "#{spec.full_name}.gemspec"
  end

  ##
  # Writes the .gemspec specification (in Ruby) to the gem home's
  # specifications directory.

  def write_spec
    open spec_file, 'w' do |file|
      spec.installed_by_version = Gem.rubygems_version

      file.puts spec.to_ruby_for_cache

      file.fsync rescue nil # for filesystems without fsync(2)
    end
  end

  ##
  # Writes the full .gemspec specification (in Ruby) to the gem home's
  # specifications/default directory.

  def write_default_spec
    File.open(default_spec_file, "w") do |file|
      file.puts spec.to_ruby
    end
  end

  ##
  # Creates windows .bat files for easy running of commands

  def generate_windows_script(filename, bindir)
    if Gem.win_platform? then
      script_name = filename + ".bat"
      script_path = File.join bindir, File.basename(script_name)
      File.open script_path, 'w' do |file|
        file.puts windows_stub_script(bindir, filename)
      end

      verbose script_path
    end
  end

  def generate_bin # :nodoc:
    return if spec.executables.nil? or spec.executables.empty?

    Dir.mkdir @bin_dir unless File.exist? @bin_dir
    raise Gem::FilePermissionError.new(@bin_dir) unless File.writable? @bin_dir

    spec.executables.each do |filename|
      filename.untaint
      bin_path = File.join gem_dir, spec.bindir, filename

      unless File.exist? bin_path then
        # TODO change this to a more useful warning
        warn "#{bin_path} maybe `gem pristine #{spec.name}` will fix it?"
        next
      end

      mode = File.stat(bin_path).mode
      FileUtils.chmod mode | 0111, bin_path unless (mode | 0111) == mode

      check_executable_overwrite filename

      if @wrappers then
        generate_bin_script filename, @bin_dir
      else
        generate_bin_symlink filename, @bin_dir
      end

    end
  end

  ##
  # Creates the scripts to run the applications in the gem.
  #--
  # The Windows script is generated in addition to the regular one due to a
  # bug or misfeature in the Windows shell's pipe.  See
  # http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-talk/193379

  def generate_bin_script(filename, bindir)
    bin_script_path = File.join bindir, formatted_program_filename(filename)

    FileUtils.rm_f bin_script_path # prior install may have been --no-wrappers

    File.open bin_script_path, 'wb', 0755 do |file|
      file.print app_script_text(filename)
    end

    verbose bin_script_path

    generate_windows_script filename, bindir
  end

  ##
  # Creates the symlinks to run the applications in the gem.  Moves
  # the symlink if the gem being installed has a newer version.

  def generate_bin_symlink(filename, bindir)
    src = File.join gem_dir, spec.bindir, filename
    dst = File.join bindir, formatted_program_filename(filename)

    if File.exist? dst then
      if File.symlink? dst then
        link = File.readlink(dst).split File::SEPARATOR
        cur_version = Gem::Version.create(link[-3].sub(/^.*-/, ''))
        return if spec.version < cur_version
      end
      File.unlink dst
    end

    FileUtils.symlink src, dst, :verbose => Gem.configuration.really_verbose
  rescue NotImplementedError, SystemCallError
    alert_warning "Unable to use symlinks, installing wrapper"
    generate_bin_script filename, bindir
  end

  ##
  # Generates a #! line for +bin_file_name+'s wrapper copying arguments if
  # necessary.
  #
  # If the :custom_shebang config is set, then it is used as a template
  # for how to create the shebang used for to run a gem's executables.
  #
  # The template supports 4 expansions:
  #
  #  $env    the path to the unix env utility
  #  $ruby   the path to the currently running ruby interpreter
  #  $exec   the path to the gem's executable
  #  $name   the name of the gem the executable is for
  #

  def shebang(bin_file_name)
    ruby_name = RbConfig::CONFIG['ruby_install_name'] if @env_shebang
    path = File.join gem_dir, spec.bindir, bin_file_name
    first_line = File.open(path, "rb") {|file| file.gets}

    if /\A#!/ =~ first_line then
      # Preserve extra words on shebang line, like "-w".  Thanks RPA.
      shebang = first_line.sub(/\A\#!.*?ruby\S*((\s+\S+)+)/, "#!#{Gem.ruby}")
      opts = $1
      shebang.strip! # Avoid nasty ^M issues.
    end

    if which = Gem.configuration[:custom_shebang]
      # replace bin_file_name with "ruby" to avoid endless loops
      which = which.gsub(/ #{bin_file_name}$/," #{RbConfig::CONFIG['ruby_install_name']}")

      which = which.gsub(/\$(\w+)/) do
        case $1
        when "env"
          @env_path ||= ENV_PATHS.find {|env_path| File.executable? env_path }
        when "ruby"
          "#{Gem.ruby}#{opts}"
        when "exec"
          bin_file_name
        when "name"
          spec.name
        end
      end

      "#!#{which}"
    elsif not ruby_name then
      "#!#{Gem.ruby}#{opts}"
    elsif opts then
      "#!/bin/sh\n'exec' #{ruby_name.dump} '-x' \"$0\" \"$@\"\n#{shebang}"
    else
      # Create a plain shebang line.
      @env_path ||= ENV_PATHS.find {|env_path| File.executable? env_path }
      "#!#{@env_path} #{ruby_name}"
    end
  end

  ##
  # Ensures the Gem::Specification written out for this gem is loadable upon
  # installation.

  def ensure_loadable_spec
    ruby = spec.to_ruby_for_cache
    ruby.untaint

    begin
      eval ruby
    rescue StandardError, SyntaxError => e
      raise Gem::InstallError,
            "The specification for #{spec.full_name} is corrupt (#{e.class})"
    end
  end

  def ensure_required_ruby_version_met # :nodoc:
    if rrv = spec.required_ruby_version then
      unless rrv.satisfied_by? Gem.ruby_version then
        raise Gem::InstallError, "#{spec.name} requires Ruby version #{rrv}."
      end
    end
  end

  def ensure_required_rubygems_version_met # :nodoc:
    if rrgv = spec.required_rubygems_version then
      unless rrgv.satisfied_by? Gem.rubygems_version then
        raise Gem::InstallError,
          "#{spec.name} requires RubyGems version #{rrgv}. " +
          "Try 'gem update --system' to update RubyGems itself."
      end
    end
  end

  def ensure_dependencies_met # :nodoc:
    deps = spec.runtime_dependencies
    deps |= spec.development_dependencies if @development

    deps.each do |dep_gem|
      ensure_dependency spec, dep_gem
    end
  end

  def process_options # :nodoc:
    @options = {
      :bin_dir      => nil,
      :env_shebang  => false,
      :force        => false,
      :only_install_dir => false,
      :post_install_message => true
    }.merge options

    @env_shebang         = options[:env_shebang]
    @force               = options[:force]
    @install_dir         = options[:install_dir]
    @gem_home            = options[:install_dir] || Gem.dir
    @ignore_dependencies = options[:ignore_dependencies]
    @format_executable   = options[:format_executable]
    @wrappers            = options[:wrappers]
    @only_install_dir    = options[:only_install_dir]

    # If the user has asked for the gem to be installed in a directory that is
    # the system gem directory, then use the system bin directory, else create
    # (or use) a new bin dir under the gem_home.
    @bin_dir             = options[:bin_dir] || Gem.bindir(gem_home)
    @development         = options[:development]
    @build_root          = options[:build_root]

    @build_args          = options[:build_args] || Gem::Command.build_args

    unless @build_root.nil?
      require 'pathname'
      @build_root = Pathname.new(@build_root).expand_path
      @bin_dir = File.join(@build_root, options[:bin_dir] || Gem.bindir(@gem_home))
      @gem_home = File.join(@build_root, @gem_home)
      alert_warning "You build with buildroot.\n  Build root: #{@build_root}\n  Bin dir: #{@bin_dir}\n  Gem home: #{@gem_home}"
    end
  end

  def check_that_user_bin_dir_is_in_path # :nodoc:
    user_bin_dir = @bin_dir || Gem.bindir(gem_home)
    user_bin_dir = user_bin_dir.gsub(File::SEPARATOR, File::ALT_SEPARATOR) if
      File::ALT_SEPARATOR

    path = ENV['PATH']
    if Gem.win_platform? then
      path = path.downcase
      user_bin_dir = user_bin_dir.downcase
    end

    path = path.split(File::PATH_SEPARATOR)

    unless path.include? user_bin_dir then
      unless !Gem.win_platform? && (path.include? user_bin_dir.sub(ENV['HOME'], '~'))
        unless self.class.path_warning then
          alert_warning "You don't have #{user_bin_dir} in your PATH,\n\t  gem executables will not run."
          self.class.path_warning = true
        end
      end
    end
  end

  def verify_gem_home(unpack = false) # :nodoc:
    FileUtils.mkdir_p gem_home
    raise Gem::FilePermissionError, gem_home unless
      unpack or File.writable?(gem_home)
  end

  ##
  # Return the text for an application file.

  def app_script_text(bin_file_name)
    return <<-TEXT
#{shebang bin_file_name}
#
# This file was generated by RubyGems.
#
# The application '#{spec.name}' is installed as part of a gem, and
# this file is here to facilitate running it.
#

require 'rubygems'

version = "#{Gem::Requirement.default}.a"

if ARGV.first
  str = ARGV.first
  str = str.dup.force_encoding("BINARY") if str.respond_to? :force_encoding
  if str =~ /\\A_(.*)_\\z/ and Gem::Version.correct?($1) then
    version = $1
    ARGV.shift
  end
end

load Gem.activate_bin_path('#{spec.name}', '#{bin_file_name}', version)
TEXT
  end

  ##
  # return the stub script text used to launch the true Ruby script

  def windows_stub_script(bindir, bin_file_name)
    ruby = Gem.ruby.gsub(/^\"|\"$/, "").tr(File::SEPARATOR, "\\")
    return <<-TEXT
@ECHO OFF
IF NOT "%~f0" == "~f0" GOTO :WinNT
@"#{ruby}" "#{File.join(bindir, bin_file_name)}" %1 %2 %3 %4 %5 %6 %7 %8 %9
GOTO :EOF
:WinNT
@"#{ruby}" "%~dpn0" %*
TEXT
  end

  ##
  # Builds extensions.  Valid types of extensions are extconf.rb files,
  # configure scripts and rakefiles or mkrf_conf files.

  def build_extensions
    builder = Gem::Ext::Builder.new spec, @build_args

    builder.build_extensions
  end

  ##
  # Logs the build +output+ in +build_dir+, then raises Gem::Ext::BuildError.
  #
  # TODO:  Delete this for RubyGems 3.  It remains for API compatibility

  def extension_build_error(build_dir, output, backtrace = nil) # :nodoc:
    builder = Gem::Ext::Builder.new spec, @build_args

    builder.build_error build_dir, output, backtrace
  end

  ##
  # Reads the file index and extracts each file into the gem directory.
  #
  # Ensures that files can't be installed outside the gem directory.

  def extract_files
    @package.extract_files gem_dir
  end

  ##
  # Extracts only the bin/ files from the gem into the gem directory.
  # This is used by default gems to allow a gem-aware stub to function
  # without the full gem installed.

  def extract_bin
    @package.extract_files gem_dir, "bin/*"
  end

  ##
  # Prefix and suffix the program filename the same as ruby.

  def formatted_program_filename(filename)
    if @format_executable then
      self.class.exec_format % File.basename(filename)
    else
      filename
    end
  end

  ##
  #
  # Return the target directory where the gem is to be installed. This
  # directory is not guaranteed to be populated.
  #

  def dir
    gem_dir.to_s
  end

  ##
  # Performs various checks before installing the gem such as the install
  # repository is writable and its directories exist, required Ruby and
  # rubygems versions are met and that dependencies are installed.
  #
  # Version and dependency checks are skipped if this install is forced.
  #
  # The dependent check will be skipped this install is ignoring dependencies.

  def pre_install_checks
    verify_gem_home options[:unpack]

    ensure_loadable_spec

    if options[:install_as_default]
      Gem.ensure_default_gem_subdirectories gem_home
    else
      Gem.ensure_gem_subdirectories gem_home
    end

    return true if @force

    ensure_required_ruby_version_met
    ensure_required_rubygems_version_met
    ensure_dependencies_met unless @ignore_dependencies

    true
  end

  ##
  # Writes the file containing the arguments for building this gem's
  # extensions.

  def write_build_info_file
    return if @build_args.empty?

    build_info_dir = File.join gem_home, 'build_info'

    FileUtils.mkdir_p build_info_dir

    build_info_file = File.join build_info_dir, "#{spec.full_name}.info"

    open build_info_file, 'w' do |io|
      @build_args.each do |arg|
        io.puts arg
      end
    end
  end

  ##
  # Writes the .gem file to the cache directory

  def write_cache_file
    cache_file = File.join gem_home, 'cache', spec.file_name
    @package.copy_to cache_file
  end

end
