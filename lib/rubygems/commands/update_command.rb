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

  def check_latest_rubygems version # :nodoc:
    if Gem.rubygems_version == version then
      say "Latest version currently installed. Aborting."
      terminate_interaction
    end

    options[:user_install] = false
  end

  def check_update_arguments # :nodoc:
    unless options[:args].empty? then
      alert_error "Gem names are not allowed with the --system option"
      terminate_interaction 1
    end
  end

  def execute

    if options[:system] then
      update_rubygems
      return
    end

    say "Updating installed gems"

    hig = highest_installed_gems

    gems_to_update = which_to_update hig, options[:args].uniq

    updated = update_gems gems_to_update

    updated_names = updated.map { |spec| spec.name }
    not_updated_names = options[:args].uniq - updated_names

    if updated.empty? then
      say "Nothing to update"
    else
      say "Gems updated: #{updated_names.join(' ')}"
      say "Gems already up-to-date: #{not_updated_names.join(' ')}" unless not_updated_names.empty?
    end
  end

  def fetch_remote_gems spec # :nodoc:
    dependency = Gem::Dependency.new spec.name, "> #{spec.version}"
    dependency.prerelease = options[:prerelease]

    fetcher = Gem::SpecFetcher.fetcher

    spec_tuples, errors = fetcher.search_for_dependency dependency

    error = errors.find { |e| e.respond_to? :exception }

    raise error if error

    spec_tuples
  end

  def highest_installed_gems # :nodoc:
    hig = {} # highest installed gems

    Gem::Specification.each do |spec|
      if hig[spec.name].nil? or hig[spec.name].version < spec.version then
        hig[spec.name] = spec
      end
    end

    hig
  end

  def highest_remote_version spec # :nodoc:
    spec_tuples = fetch_remote_gems spec

    matching_gems = spec_tuples.select do |g,_|
      g.name == spec.name and g.match_platform?
    end

    highest_remote_gem = matching_gems.max_by { |g,_| g.version }

    highest_remote_gem ||= [Gem::NameTuple.null]

    highest_remote_gem.first.version
  end

  def install_rubygems version # :nodoc:
    args = update_rubygems_arguments

    update_dir = File.join Gem.dir, 'gems', "rubygems-update-#{version}"

    Dir.chdir update_dir do
      say "Installing RubyGems #{version}"

      # Make sure old rubygems isn't loaded
      old = ENV["RUBYOPT"]
      ENV.delete("RUBYOPT") if old
      installed = system Gem.ruby, 'setup.rb', *args
      say "RubyGems system software updated" if installed
      ENV["RUBYOPT"] = old if old
    end
  end

  def rubygems_target_version
    version = options[:system]
    update_latest = version == true

    if update_latest then
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
      'rubygems-update' => rubygems_update
    }

    gems_to_update = which_to_update hig, options[:args], :system
    _, up_ver   = gems_to_update.first

    target = if update_latest then
               up_ver
             else
               version
             end

    return target, requirement
  end

  def update_gem name, version = Gem::Requirement.default
    return if @updated.any? { |spec| spec.name == name }

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

  def update_gems gems_to_update
    gems_to_update.uniq.sort.each do |(name, version)|
      update_gem name, version
    end

    @updated
  end

  ##
  # Update RubyGems software to the latest version.

  def update_rubygems
    check_update_arguments

    version, requirement = rubygems_target_version

    check_latest_rubygems version

    update_gem 'rubygems-update', version

    installed_gems = Gem::Specification.find_all_by_name 'rubygems-update', requirement
    version        = installed_gems.first.version

    install_rubygems version
  end

  def update_rubygems_arguments # :nodoc:
    args = []
    args << '--prefix' << Gem.prefix if Gem.prefix
    # TODO use --document for >= 1.9 , --no-rdoc --no-ri < 1.9
    args << '--no-rdoc' unless options[:document].include? 'rdoc'
    args << '--no-ri'   unless options[:document].include? 'ri'
    args << '--no-format-executable' if options[:no_format_executable]
    args << '--previous-version' << Gem::VERSION if
      options[:system] == true or
        Gem::Version.new(options[:system]) >= Gem::Version.new(2)
    args
  end

  def which_to_update highest_installed_gems, gem_names, system = false
    result = []

    highest_installed_gems.each do |l_name, l_spec|
      next if not gem_names.empty? and
              gem_names.none? { |name| name == l_spec.name }

      highest_remote_ver = highest_remote_version l_spec

      if system or (l_spec.version < highest_remote_ver) then
        result << [l_spec.name, [l_spec.version, highest_remote_ver].max]
      end
    end

    result
  end

end
