# frozen_string_literal: true
require 'rubygems/command'
require 'rubygems/command_manager'
require 'rubygems/dependency_installer'
require 'rubygems/install_update_options'
require 'rubygems/local_remote_options'
require 'rubygems/spec_fetcher'
require 'rubygems/version_option'
require 'rubygems/install_message' # must come before rdoc for messaging
require 'rubygems/rdoc'

class Gem::Commands::UpdateCommand < Gem::Command
  include Gem::InstallUpdateOptions
  include Gem::LocalRemoteOptions
  include Gem::VersionOption

  attr_reader :installer # :nodoc:

  attr_reader :updated # :nodoc:

  def initialize
    super 'update', 'Update installed gems to the latest version',
      :document => %w[rdoc ri],
      :force    => false

    add_install_update_options

    OptionParser.accept Gem::Version do |value|
      Gem::Version.new value

      value
    end

    add_option('--system [VERSION]', Gem::Version,
               'Update the RubyGems system software') do |value, options|
      value = true unless value

      options[:system] = value
    end

    add_local_remote_options
    add_platform_option
    add_prerelease_option "as update targets"

    @updated   = []
    @installer = nil
  end

  def arguments # :nodoc:
    "GEMNAME       name of gem to update"
  end

  def defaults_str # :nodoc:
    "--document --no-force --install-dir #{Gem.dir}"
  end

  def description # :nodoc:
    <<-EOF
The update command will update your gems to the latest version.

The update command does not remove the previous version. Use the cleanup
command to remove old versions.
    EOF
  end

  def usage # :nodoc:
    "#{program_name} GEMNAME [GEMNAME ...]"
  end

  def check_latest_rubygems(version) # :nodoc:
    if Gem.rubygems_version == version
      say "Latest version already installed. Done."
      terminate_interaction
    end
  end

  def check_oldest_rubygems(version) # :nodoc:
    if oldest_supported_version > version
      alert_error "rubygems #{version} is not supported. The oldest supported version is #{oldest_supported_version}"
      terminate_interaction 1
    end
  end

  def check_update_arguments # :nodoc:
    unless options[:args].empty?
      alert_error "Gem names are not allowed with the --system option"
      terminate_interaction 1
    end
  end

  def execute
    if options[:system]
      update_rubygems
      return
    end

    gems_to_update = which_to_update(
      highest_installed_gems,
      options[:args].uniq
    )

    if options[:explain]
      say "Gems to update:"

      gems_to_update.each do |name_tuple|
        say "  #{name_tuple.full_name}"
      end

      return
    end

    say "Updating installed gems"

    updated = update_gems gems_to_update

    updated_names = updated.map {|spec| spec.name }
    not_updated_names = options[:args].uniq - updated_names

    if updated.empty?
      say "Nothing to update"
    else
      say "Gems updated: #{updated_names.join(' ')}"
      say "Gems already up-to-date: #{not_updated_names.join(' ')}" unless not_updated_names.empty?
    end
  end

  def fetch_remote_gems(spec) # :nodoc:
    dependency = Gem::Dependency.new spec.name, "> #{spec.version}"
    dependency.prerelease = options[:prerelease]

    fetcher = Gem::SpecFetcher.fetcher

    spec_tuples, errors = fetcher.search_for_dependency dependency

    error = errors.find {|e| e.respond_to? :exception }

    raise error if error

    spec_tuples
  end

  def highest_installed_gems # :nodoc:
    hig = {} # highest installed gems

    # Get only gem specifications installed as --user-install
    Gem::Specification.dirs = Gem.user_dir if options[:user_install]

    Gem::Specification.each do |spec|
      if hig[spec.name].nil? or hig[spec.name].version < spec.version
        hig[spec.name] = spec
      end
    end

    hig
  end

  def highest_remote_name_tuple(spec) # :nodoc:
    spec_tuples = fetch_remote_gems spec

    matching_gems = spec_tuples.select do |g,_|
      g.name == spec.name and g.match_platform?
    end

    highest_remote_gem = matching_gems.max

    highest_remote_gem ||= [Gem::NameTuple.null]

    highest_remote_gem.first
  end

  def install_rubygems(version) # :nodoc:
    args = update_rubygems_arguments

    update_dir = File.join Gem.dir, 'gems', "rubygems-update-#{version}"

    Dir.chdir update_dir do
      say "Installing RubyGems #{version}" unless options[:silent]

      installed = preparing_gem_layout_for(version) do
        system Gem.ruby, '--disable-gems', 'setup.rb', *args
      end

      say "RubyGems system software updated" if installed unless options[:silent]
    end
  end

  def preparing_gem_layout_for(version)
    if Gem::Version.new(version) >= Gem::Version.new("3.2.a")
      yield
    else
      require "tmpdir"
      tmpdir = Dir.mktmpdir
      FileUtils.mv Gem.plugindir, tmpdir

      status = yield

      if status
        FileUtils.rm_rf tmpdir
      else
        FileUtils.mv File.join(tmpdir, "plugins"), Gem.plugindir
      end

      status
    end
  end

  def rubygems_target_version
    version = options[:system]
    update_latest = version == true

    if update_latest
      version     = Gem::Version.new     Gem::VERSION
      requirement = Gem::Requirement.new ">= #{Gem::VERSION}"
    else
      version     = Gem::Version.new     version
      requirement = Gem::Requirement.new version
    end

    rubygems_update         = Gem::Specification.new
    rubygems_update.name    = 'rubygems-update'
    rubygems_update.version = version

    hig = {
      'rubygems-update' => rubygems_update,
    }

    gems_to_update = which_to_update hig, options[:args], :system
    up_ver = gems_to_update.first.version

    target = if update_latest
               up_ver
             else
               version
             end

    return target, requirement
  end

  def update_gem(name, version = Gem::Requirement.default)
    return if @updated.any? {|spec| spec.name == name }

    update_options = options.dup
    update_options[:prerelease] = version.prerelease?

    @installer = Gem::DependencyInstaller.new update_options

    say "Updating #{name}"
    begin
      @installer.install name, Gem::Requirement.new(version)
    rescue Gem::InstallError, Gem::DependencyError => e
      alert_error "Error installing #{name}:\n\t#{e.message}"
    end

    @installer.installed_gems.each do |spec|
      @updated << spec
    end
  end

  def update_gems(gems_to_update)
    gems_to_update.uniq.sort.each do |name_tuple|
      update_gem name_tuple.name, name_tuple.version
    end

    @updated
  end

  ##
  # Update RubyGems software to the latest version.

  def update_rubygems
    if Gem.disable_system_update_message
      alert_error Gem.disable_system_update_message
      terminate_interaction 1
    end

    check_update_arguments

    version, requirement = rubygems_target_version

    check_latest_rubygems version

    check_oldest_rubygems version

    update_gem 'rubygems-update', version

    installed_gems = Gem::Specification.find_all_by_name 'rubygems-update', requirement
    version        = installed_gems.first.version

    install_rubygems version
  end

  def update_rubygems_arguments # :nodoc:
    args = []
    args << '--silent' if options[:silent]
    args << '--prefix' << Gem.prefix if Gem.prefix
    args << '--no-document' unless options[:document].include?('rdoc') || options[:document].include?('ri')
    args << '--no-format-executable' if options[:no_format_executable]
    args << '--previous-version' << Gem::VERSION if
      options[:system] == true or
        Gem::Version.new(options[:system]) >= Gem::Version.new(2)
    args
  end

  def which_to_update(highest_installed_gems, gem_names, system = false)
    result = []

    highest_installed_gems.each do |l_name, l_spec|
      next if not gem_names.empty? and
              gem_names.none? {|name| name == l_spec.name }

      highest_remote_tup = highest_remote_name_tuple l_spec
      highest_remote_ver = highest_remote_tup.version
      highest_installed_ver = l_spec.version

      if system or (highest_installed_ver < highest_remote_ver)
        result << Gem::NameTuple.new(l_spec.name, [highest_installed_ver, highest_remote_ver].max, highest_remote_tup.platform)
      end
    end

    result
  end

  private

  def oldest_supported_version
    # for Ruby 2.3
    @oldest_supported_version ||= Gem::Version.new("2.5.2")
  end
end
