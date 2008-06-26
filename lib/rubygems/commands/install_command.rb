require 'rubygems/command'
require 'rubygems/doc_manager'
require 'rubygems/install_update_options'
require 'rubygems/dependency_installer'
require 'rubygems/local_remote_options'
require 'rubygems/validator'
require 'rubygems/version_option'

class Gem::Commands::InstallCommand < Gem::Command

  include Gem::VersionOption
  include Gem::LocalRemoteOptions
  include Gem::InstallUpdateOptions

  def initialize
    defaults = Gem::DependencyInstaller::DEFAULT_OPTIONS.merge({
      :generate_rdoc => true,
      :generate_ri   => true,
      :format_executable => false,
      :test => false,
      :version => Gem::Requirement.default,
    })

    super 'install', 'Install a gem into the local repository', defaults

    add_install_update_options
    add_local_remote_options
    add_platform_option
    add_version_option
  end

  def arguments # :nodoc:
    "GEMNAME       name of gem to install"
  end

  def defaults_str # :nodoc:
    "--both --version '#{Gem::Requirement.default}' --rdoc --ri --no-force\n" \
    "--no-test --install-dir #{Gem.dir}"
  end

  def usage # :nodoc:
    "#{program_name} GEMNAME [GEMNAME ...] [options] -- --build-flags"
  end

  def execute
    if options[:include_dependencies] then
      alert "`gem install -y` is now default and will be removed"
      alert "use --ignore-dependencies to install only the gems you list"
    end

    installed_gems = []

    ENV.delete 'GEM_PATH' if options[:install_dir].nil? and RUBY_VERSION > '1.9'

    install_options = {
      :env_shebang => options[:env_shebang],
      :domain => options[:domain],
      :force => options[:force],
      :format_executable => options[:format_executable],
      :ignore_dependencies => options[:ignore_dependencies],
      :install_dir => options[:install_dir],
      :security_policy => options[:security_policy],
      :wrappers => options[:wrappers],
      :bin_dir => options[:bin_dir],
      :development => options[:development],
    }

    exit_code = 0

    get_all_gem_names.each do |gem_name|
      begin
        inst = Gem::DependencyInstaller.new install_options
        inst.install gem_name, options[:version]

        inst.installed_gems.each do |spec|
          say "Successfully installed #{spec.full_name}"
        end

        installed_gems.push(*inst.installed_gems)
      rescue Gem::InstallError => e
        alert_error "Error installing #{gem_name}:\n\t#{e.message}"
        exit_code |= 1
      rescue Gem::GemNotFoundException => e
        alert_error e.message
        exit_code |= 2
#      rescue => e
#        # TODO: Fix this handle to allow the error to propagate to
#        # the top level handler.  Examine the other errors as
#        # well.  This implementation here looks suspicious to me --
#        # JimWeirich (4/Jan/05)
#        alert_error "Error installing gem #{gem_name}: #{e.message}"
#        return
      end
    end

    unless installed_gems.empty? then
      gems = installed_gems.length == 1 ? 'gem' : 'gems'
      say "#{installed_gems.length} #{gems} installed"
    end

    # NOTE: *All* of the RI documents must be generated first.
    # For some reason, RI docs cannot be generated after any RDoc
    # documents are generated.

    if options[:generate_ri] then
      installed_gems.each do |gem|
        Gem::DocManager.new(gem, options[:rdoc_args]).generate_ri
      end
    end

    if options[:generate_rdoc] then
      installed_gems.each do |gem|
        Gem::DocManager.new(gem, options[:rdoc_args]).generate_rdoc
      end
    end

    if options[:test] then
      installed_gems.each do |spec|
        gem_spec = Gem::SourceIndex.from_installed_gems.search(spec.name, spec.version.version).first
        result = Gem::Validator.new.unit_test(gem_spec)
        if result and not result.passed?
          unless ask_yes_no("...keep Gem?", true) then
            Gem::Uninstaller.new(spec.name, :version => spec.version.version).uninstall
          end
        end
      end
    end

    raise Gem::SystemExitException, exit_code
  end

end

