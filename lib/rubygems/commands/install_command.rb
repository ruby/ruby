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
      :version           => Gem::Requirement.default,
      :without_groups    => [],
    })

    super 'install', 'Install a gem into the local repository', defaults

    add_install_update_options
    add_local_remote_options
    add_platform_option
    add_version_option
    add_prerelease_option "to be installed. (Only for listed gems)"

    add_option(:"Install/Update", '-g', '--file [FILE]',
               'Read from a gem dependencies API file and',
               'install the listed gems') do |v,o|
      v = Gem::GEM_DEP_FILES.find do |file|
        File.exist? file
      end unless v

      unless v then
        message = v ? v : "(tried #{Gem::GEM_DEP_FILES.join ', '})"

        raise OptionParser::InvalidArgument,
                "cannot find gem dependencies file #{message}"
      end

      o[:gemdeps] = v
    end

    add_option(:"Install/Update", '--without GROUPS', Array,
               'Omit the named groups (comma separated)',
               'when installing from a gem dependencies',
               'file') do |v,o|
      o[:without_groups].concat v.map { |without| without.intern }
    end

    add_option(:"Install/Update", '--default',
               'Add the gem\'s full specification to',
               'specifications/default and extract only its bin') do |v,o|
      o[:install_as_default] = v
    end

    add_option(:"Install/Update", '--explain',
               'Rather than install the gems, indicate which would',
               'be installed') do |v,o|
      o[:explain] = v
    end

    @installed_specs = []
  end

  def arguments # :nodoc:
    "GEMNAME       name of gem to install"
  end

  def defaults_str # :nodoc:
    "--both --version '#{Gem::Requirement.default}' --document --no-force\n" +
    "--install-dir #{Gem.dir}"
  end

  def description # :nodoc:
    <<-EOF
The install command installs local or remote gem into a gem repository.

For gems with executables ruby installs a wrapper file into the executable
directory by default.  This can be overridden with the --no-wrappers option.
The wrapper allows you to choose among alternate gem versions using _version_.

For example `rake _0.7.3_ --version` will run rake version 0.7.3 if a newer
version is also installed.

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

    EOF
  end

  def usage # :nodoc:
    "#{program_name} GEMNAME [GEMNAME ...] [options] -- --build-flags"
  end

  def check_install_dir # :nodoc:
    if options[:install_dir] and options[:user_install] then
      alert_error "Use --install-dir or --user-install but not both"
      terminate_interaction 1
    end
  end

  def check_version # :nodoc:
    if options[:version] != Gem::Requirement.default and
         get_all_gem_names.size > 1 then
      alert_error "Can't use --version w/ multiple gems. Use name:ver instead."
      terminate_interaction 1
    end
  end

  def execute
    if options.include? :gemdeps then
      install_from_gemdeps
      return # not reached
    end

    @installed_specs = []

    ENV.delete 'GEM_PATH' if options[:install_dir].nil? and RUBY_VERSION > '1.9'

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

  def install_gem name, version # :nodoc:
    return if options[:conservative] and
      not Gem::Dependency.new(name, version).matching_specs.empty?

    req = Gem::Requirement.create(version)

    if options[:ignore_dependencies] then
      install_gem_without_dependencies name, req
    else
      inst = Gem::DependencyInstaller.new options

      if options[:explain]
        request_set = inst.resolve_dependencies name, req

        puts "Gems to install:"

        request_set.specs.map { |s| s.full_name }.sort.each do |s|
          puts "  #{s}"
        end

        return
      else
        inst.install name, req
      end

      @installed_specs.push(*inst.installed_gems)

      show_install_errors inst.errors
    end
  end

  def install_gem_without_dependencies name, req # :nodoc:
    gem = nil

    if remote? then
      dependency = Gem::Dependency.new name, req
      dependency.prerelease = options[:prerelease]

      fetcher = Gem::RemoteFetcher.fetcher
      gem = fetcher.download_to_cache dependency
    end

    if local? and not gem then
      source = Gem::Source::Local.new
      spec = source.find_gem name, req

      gem = source.download spec
    end

    inst = Gem::Installer.new gem, options
    inst.install

    @installed_specs.push(inst.spec)
  end

  def install_gems # :nodoc:
    exit_code = 0

    get_all_gem_names_and_versions.each do |gem_name, gem_version|
      gem_version ||= options[:version]

      begin
        install_gem gem_name, gem_version
      rescue Gem::InstallError => e
        alert_error "Error installing #{gem_name}:\n\t#{e.message}"
        exit_code |= 1
      rescue Gem::GemNotFoundException => e
        show_lookup_failure e.name, e.version, e.errors, options[:domain]

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

  def show_install_errors errors # :nodoc:
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

