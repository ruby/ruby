require 'rubygems/command'
require 'rubygems/command_manager'
require 'rubygems/install_update_options'
require 'rubygems/local_remote_options'
require 'rubygems/spec_fetcher'
require 'rubygems/version_option'
require 'rubygems/commands/install_command'

class Gem::Commands::UpdateCommand < Gem::Command

  include Gem::InstallUpdateOptions
  include Gem::LocalRemoteOptions
  include Gem::VersionOption

  def initialize
    super 'update',
          'Update the named gems (or all installed gems) in the local repository',
      :generate_rdoc => true,
      :generate_ri => true,
      :force => false,
      :test => false

    add_install_update_options

    add_option('--system',
               'Update the RubyGems system software') do |value, options|
      options[:system] = value
    end

    add_local_remote_options

    add_platform_option
  end

  def arguments # :nodoc:
    "GEMNAME       name of gem to update"
  end

  def defaults_str # :nodoc:
    "--rdoc --ri --no-force --no-test --install-dir #{Gem.dir}"
  end

  def usage # :nodoc:
    "#{program_name} GEMNAME [GEMNAME ...]"
  end

  def execute
    if options[:system] then
      say "Updating RubyGems"

      unless options[:args].empty? then
        fail "No gem names are allowed with the --system option"
      end

      options[:args] = ["rubygems-update"]
    else
      say "Updating installed gems"
    end

    hig = {} # highest installed gems

    Gem.source_index.each do |name, spec|
      if hig[spec.name].nil? or hig[spec.name].version < spec.version then
        hig[spec.name] = spec
      end
    end

    gems_to_update = which_to_update hig, options[:args]

    updated = []

    installer = Gem::DependencyInstaller.new options

    gems_to_update.uniq.sort.each do |name|
      next if updated.any? { |spec| spec.name == name }

      say "Updating #{name}"
      installer.install name

      installer.installed_gems.each do |spec|
        updated << spec
        say "Successfully installed #{spec.full_name}"
      end
    end

    if gems_to_update.include? "rubygems-update" then
      latest_ruby_gem = remote_gemspecs.select do |s|
        s.name == 'rubygems-update'
      end

      latest_ruby_gem = latest_ruby_gem.sort_by { |s| s.version }.last

      say "Updating version of RubyGems to #{latest_ruby_gem.version}"
      installed = do_rubygems_update latest_ruby_gem.version

      say "RubyGems system software updated" if installed
    else
      if updated.empty? then
        say "Nothing to update"
      else
        say "Gems updated: #{updated.map { |spec| spec.name }.join ', '}"
      end
    end
  end

  def do_rubygems_update(version)
    args = []
    args.push '--prefix', Gem.prefix unless Gem.prefix.nil?
    args << '--no-rdoc' unless options[:generate_rdoc]
    args << '--no-ri' unless options[:generate_ri]
    args << '--no-format-executable' if options[:no_format_executable]

    update_dir = File.join Gem.dir, 'gems', "rubygems-update-#{version}"

    success = false

    Dir.chdir update_dir do
      say "Installing RubyGems #{version}"
      setup_cmd = "#{Gem.ruby} setup.rb #{args.join ' '}"

      # Make sure old rubygems isn't loaded
      old = ENV["RUBYOPT"]
      ENV.delete("RUBYOPT")
      system setup_cmd
      ENV["RUBYOPT"] = old if old
    end
  end

  def which_to_update(highest_installed_gems, gem_names)
    result = []

    highest_installed_gems.each do |l_name, l_spec|
      next if not gem_names.empty? and
              gem_names.all? { |name| /#{name}/ !~ l_spec.name }

      dependency = Gem::Dependency.new l_spec.name, "> #{l_spec.version}"

      begin
        fetcher = Gem::SpecFetcher.fetcher
        spec_tuples = fetcher.find_matching dependency
      rescue Gem::RemoteFetcher::FetchError => e
        raise unless fetcher.warn_legacy e do
          require 'rubygems/source_info_cache'

          dependency.name = '' if dependency.name == //

          specs = Gem::SourceInfoCache.search_with_source dependency

          spec_tuples = specs.map do |spec, source_uri|
            [[spec.name, spec.version, spec.original_platform], source_uri]
          end
        end
      end

      matching_gems = spec_tuples.select do |(name, version, platform),|
        name == l_name and Gem::Platform.match platform
      end

      highest_remote_gem = matching_gems.sort_by do |(name, version),|
        version
      end.last

      if highest_remote_gem and
         l_spec.version < highest_remote_gem.first[1] then
        result << l_name
      end
    end

    result
  end

end

