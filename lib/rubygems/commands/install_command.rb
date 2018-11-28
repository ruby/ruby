# frozen_string_literal: true
require 'rubygems/command'
require 'rubygems/install_update_options'
require 'rubygems/dependency_installer'
require 'rubygems/local_remote_options'
require 'rubygems/validator'
require 'rubygems/version_option'

##
# Gem installer command line tool
#
# See `gem help install`

class Gem::Commands::InstallCommand < Gem::Command

  attr_reader :installed_specs # :nodoc:

  include Gem::VersionOption
  include Gem::LocalRemoteOptions
  include Gem::InstallUpdateOptions

  def initialize
    defaults = Gem::DependencyInstaller::DEFAULT_OPTIONS.merge({
      :format_executable => false,
      :lock              => true,
      :suggest_alternate => true,
      :version           => Gem::Requirement.default,
      :without_groups    => [],
    })

    super 'install', 'Install a gem into the local repository', defaults

    add_install_update_options
    add_local_remote_options
    add_platform_option
    add_version_option
    add_prerelease_option "to be installed. (Only for listed gems)"

    @installed_specs = []
  end

  def arguments # :nodoc:
    "GEMNAME       name of gem to install"
  end

  def defaults_str # :nodoc:
    "--both --version '#{Gem::Requirement.default}' --document --no-force\n" +
    "--install-dir #{Gem.dir} --lock"
  end

  def description # :nodoc:
    <<-EOF
The install command installs local or remote gem into a gem repository.

For gems with executables ruby installs a wrapper file into the executable
directory by default.  This can be overridden with the --no-wrappers option.
The wrapper allows you to choose among alternate gem versions using _version_.

For example `rake _0.7.3_ --version` will run rake version 0.7.3 if a newer
version is also installed.

Gem Dependency Files
====================

RubyGems can install a consistent set of gems across multiple environments
using `gem install -g` when a gem dependencies file (gem.deps.rb, Gemfile or
Isolate) is present.  If no explicit file is given RubyGems attempts to find
one in the current directory.

When the RUBYGEMS_GEMDEPS environment variable is set to a gem dependencies
file the gems from that file will be activated at startup time.  Set it to a
specific filename or to "-" to have RubyGems automatically discover the gem
dependencies file by walking up from the current directory.

NOTE: Enabling automatic discovery on multiuser systems can lead to
execution of arbitrary code when used from directories outside your control.

Extension Install Failures
==========================

If an extension fails to compile during gem installation the gem
specification is not written out, but the gem remains unpacked in the
repository.  You may need to specify the path to the library's headers and
libraries to continue.  You can do this by adding a -- between RubyGems'
options and the extension's build options:

  $ gem install some_extension_gem
  [build fails]
  Gem files will remain installed in \\
  /path/to/gems/some_extension_gem-1.0 for inspection.
  Results logged to /path/to/gems/some_extension_gem-1.0/gem_make.out
  $ gem install some_extension_gem -- --with-extension-lib=/path/to/lib
  [build succeeds]
  $ gem list some_extension_gem

  *** LOCAL GEMS ***

  some_extension_gem (1.0)
  $

If you correct the compilation errors by editing the gem files you will need
to write the specification by hand.  For example:

  $ gem install some_extension_gem
  [build fails]
  Gem files will remain installed in \\
  /path/to/gems/some_extension_gem-1.0 for inspection.
  Results logged to /path/to/gems/some_extension_gem-1.0/gem_make.out
  $ [cd /path/to/gems/some_extension_gem-1.0]
  $ [edit files or what-have-you and run make]
  $ gem spec ../../cache/some_extension_gem-1.0.gem --ruby > \\
             ../../specifications/some_extension_gem-1.0.gemspec
  $ gem list some_extension_gem

  *** LOCAL GEMS ***

  some_extension_gem (1.0)
  $

Command Alias
==========================

You can use `i` command instead of `install`.

  $ gem i GEMNAME

    EOF
  end

  def usage # :nodoc:
    "#{program_name} GEMNAME [GEMNAME ...] [options] -- --build-flags"
  end

  def check_install_dir # :nodoc:
    if options[:install_dir] and options[:user_install]
      alert_error "Use --install-dir or --user-install but not both"
      terminate_interaction 1
    end
  end

  def check_version # :nodoc:
    if options[:version] != Gem::Requirement.default and
         get_all_gem_names.size > 1
      alert_error "Can't use --version with multiple gems. You can specify multiple gems with" \
                  " version requirements using `gem install 'my_gem:1.0.0' 'my_other_gem:~>2.0.0'`"
      terminate_interaction 1
    end
  end

  def execute
    if options.include? :gemdeps
      install_from_gemdeps
      return # not reached
    end

    @installed_specs = []

    ENV.delete 'GEM_PATH' if options[:install_dir].nil?

    check_install_dir
    check_version

    load_hooks

    exit_code = install_gems

    show_installed

    terminate_interaction exit_code
  end

  def install_from_gemdeps # :nodoc:
    require 'rubygems/request_set'
    rs = Gem::RequestSet.new

    specs = rs.install_from_gemdeps options do |req, inst|
      s = req.full_spec

      if inst
        say "Installing #{s.name} (#{s.version})"
      else
        say "Using #{s.name} (#{s.version})"
      end
    end

    @installed_specs = specs

    terminate_interaction
  end

  def install_gem(name, version) # :nodoc:
    return if options[:conservative] and
      not Gem::Dependency.new(name, version).matching_specs.empty?

    req = Gem::Requirement.create(version)

    if options[:ignore_dependencies]
      install_gem_without_dependencies name, req
    else
      inst = Gem::DependencyInstaller.new options
      request_set = inst.resolve_dependencies name, req

      if options[:explain]
        puts "Gems to install:"

        request_set.sorted_requests.each do |s|
          puts "  #{s.full_name}"
        end

        return
      else
        @installed_specs.concat request_set.install options
      end

      show_install_errors inst.errors
    end
  end

  def install_gem_without_dependencies(name, req) # :nodoc:
    gem = nil

    if local?
      if name =~ /\.gem$/ and File.file? name
        source = Gem::Source::SpecificFile.new name
        spec = source.spec
      else
        source = Gem::Source::Local.new
        spec = source.find_gem name, req
      end
      gem = source.download spec if spec
    end

    if remote? and not gem
      dependency = Gem::Dependency.new name, req
      dependency.prerelease = options[:prerelease]

      fetcher = Gem::RemoteFetcher.fetcher
      gem = fetcher.download_to_cache dependency
    end

    inst = Gem::Installer.at gem, options
    inst.install

    require 'rubygems/dependency_installer'
    dinst = Gem::DependencyInstaller.new options
    dinst.installed_gems.replace [inst.spec]

    Gem.done_installing_hooks.each do |hook|
      hook.call dinst, [inst.spec]
    end unless Gem.done_installing_hooks.empty?

    @installed_specs.push(inst.spec)
  end

  def install_gems # :nodoc:
    exit_code = 0

    get_all_gem_names_and_versions.each do |gem_name, gem_version|
      gem_version ||= options[:version]
      domain = options[:domain]
      domain = :local unless options[:suggest_alternate]

      begin
        install_gem gem_name, gem_version
      rescue Gem::InstallError => e
        alert_error "Error installing #{gem_name}:\n\t#{e.message}"
        exit_code |= 1
      rescue Gem::GemNotFoundException => e
        show_lookup_failure e.name, e.version, e.errors, domain

        exit_code |= 2
      rescue Gem::UnsatisfiableDependencyError => e
        show_lookup_failure e.name, e.version, e.errors, domain,
                            "'#{gem_name}' (#{gem_version})"

        exit_code |= 2
      end
    end

    exit_code
  end

  ##
  # Loads post-install hooks

  def load_hooks # :nodoc:
    if options[:install_as_default]
      require 'rubygems/install_default_message'
    else
      require 'rubygems/install_message'
    end
    require 'rubygems/rdoc'
  end

  def show_install_errors(errors) # :nodoc:
    return unless errors

    errors.each do |x|
      return unless Gem::SourceFetchProblem === x

      msg = "Unable to pull data from '#{x.source.uri}': #{x.error.message}"

      alert_warning msg
    end
  end

  def show_installed # :nodoc:
    return if @installed_specs.empty?

    gems = @installed_specs.length == 1 ? 'gem' : 'gems'
    say "#{@installed_specs.length} #{gems} installed"
  end

end
