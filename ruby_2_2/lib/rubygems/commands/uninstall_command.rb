require 'rubygems/command'
require 'rubygems/version_option'
require 'rubygems/uninstaller'
require 'fileutils'

##
# Gem uninstaller command line tool
#
# See `gem help uninstall`

class Gem::Commands::UninstallCommand < Gem::Command

  include Gem::VersionOption

  def initialize
    super 'uninstall', 'Uninstall gems from the local repository',
          :version => Gem::Requirement.default, :user_install => true,
          :check_dev => false, :vendor => false

    add_option('-a', '--[no-]all',
      'Uninstall all matching versions'
      ) do |value, options|
      options[:all] = value
    end

    add_option('-I', '--[no-]ignore-dependencies',
               'Ignore dependency requirements while',
               'uninstalling') do |value, options|
      options[:ignore] = value
    end

    add_option('-D', '--[no-]-check-development',
               'Check development dependencies while uninstalling',
               '(default: false)') do |value, options|
      options[:check_dev] = value
    end

    add_option('-x', '--[no-]executables',
                 'Uninstall applicable executables without',
                 'confirmation') do |value, options|
      options[:executables] = value
    end

    add_option('-i', '--install-dir DIR',
               'Directory to uninstall gem from') do |value, options|
      options[:install_dir] = File.expand_path(value)
    end

    add_option('-n', '--bindir DIR',
               'Directory to remove binaries from') do |value, options|
      options[:bin_dir] = File.expand_path(value)
    end

    add_option('--[no-]user-install',
               'Uninstall from user\'s home directory',
               'in addition to GEM_HOME.') do |value, options|
      options[:user_install] = value
    end

    add_option('--[no-]format-executable',
               'Assume executable names match Ruby\'s prefix and suffix.') do |value, options|
      options[:format_executable] = value
    end

    add_option('--[no-]force',
               'Uninstall all versions of the named gems',
               'ignoring dependencies') do |value, options|
      options[:force] = value
    end

    add_option('--[no-]abort-on-dependent',
               'Prevent uninstalling gems that are',
               'depended on by other gems.') do |value, options|
      options[:abort_on_dependent] = value
    end

    add_version_option
    add_platform_option

    add_option('--vendor',
               'Uninstall gem from the vendor directory.',
               'Only for use by gem repackagers.') do |value, options|
      unless Gem.vendor_dir then
        raise OptionParser::InvalidOption.new 'your platform is not supported'
      end

      alert_warning 'Use your OS package manager to uninstall vendor gems'
      options[:vendor] = true
      options[:install_dir] = Gem.vendor_dir
    end
  end

  def arguments # :nodoc:
    "GEMNAME       name of gem to uninstall"
  end

  def defaults_str # :nodoc:
    "--version '#{Gem::Requirement.default}' --no-force " +
    "--user-install"
  end

  def description # :nodoc:
    <<-EOF
The uninstall command removes a previously installed gem.

RubyGems will ask for confirmation if you are attempting to uninstall a gem
that is a dependency of an existing gem.  You can use the
--ignore-dependencies option to skip this check.
    EOF
  end

  def usage # :nodoc:
    "#{program_name} GEMNAME [GEMNAME ...]"
  end

  def execute
    if options[:all] and not options[:args].empty? then
      uninstall_specific
    elsif options[:all] then
      uninstall_all
    else
      uninstall_specific
    end
  end

  def uninstall_all
    specs = Gem::Specification.reject { |spec| spec.default_gem? }

    specs.each do |spec|
      options[:version] = spec.version

      begin
        Gem::Uninstaller.new(spec.name, options).uninstall
      rescue Gem::InstallError
      end
    end

    alert "Uninstalled all gems in #{options[:install_dir]}"
  end

  def uninstall_specific
    deplist = Gem::DependencyList.new

    get_all_gem_names.uniq.each do |name|
      Gem::Specification.find_all_by_name(name).each do |spec|
        deplist.add spec
      end
    end

    deps = deplist.strongly_connected_components.flatten.reverse

    deps.map(&:name).uniq.each do |gem_name|
      begin
        Gem::Uninstaller.new(gem_name, options).uninstall
      rescue Gem::GemNotInHomeException => e
        spec = e.spec
        alert("In order to remove #{spec.name}, please execute:\n" +
              "\tgem uninstall #{spec.name} --install-dir=#{spec.installation_path}")
      end
    end
  end

end

