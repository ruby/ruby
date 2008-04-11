require 'rubygems'
require 'rubygems/dependency_list'
require 'rubygems/installer'
require 'rubygems/source_info_cache'
require 'rubygems/user_interaction'

class Gem::DependencyInstaller

  include Gem::UserInteraction

  attr_reader :gems_to_install
  attr_reader :installed_gems

  DEFAULT_OPTIONS = {
    :env_shebang => false,
    :domain => :both, # HACK dup
    :force => false,
    :format_executable => false, # HACK dup
    :ignore_dependencies => false,
    :security_policy => nil, # HACK NoSecurity requires OpenSSL.  AlmostNo? Low?
    :wrappers => true
  }

  ##
  # Creates a new installer instance.
  #
  # Options are:
  # :env_shebang:: See Gem::Installer::new.
  # :domain:: :local, :remote, or :both.  :local only searches gems in the
  #           current directory.  :remote searches only gems in Gem::sources.
  #           :both searches both.
  # :force:: See Gem::Installer#install.
  # :format_executable:: See Gem::Installer#initialize.
  # :ignore_dependencies: Don't install any dependencies.
  # :install_dir: See Gem::Installer#install.
  # :security_policy: See Gem::Installer::new and Gem::Security.
  # :wrappers: See Gem::Installer::new
  def initialize(options = {})
    options = DEFAULT_OPTIONS.merge options
    @env_shebang = options[:env_shebang]
    @domain = options[:domain]
    @force = options[:force]
    @format_executable = options[:format_executable]
    @ignore_dependencies = options[:ignore_dependencies]
    @install_dir = options[:install_dir] || Gem.dir
    @security_policy = options[:security_policy]
    @wrappers = options[:wrappers]
    @bin_dir = options[:bin_dir]

    @installed_gems = []
  end

  ##
  # Returns a list of pairs of gemspecs and source_uris that match
  # Gem::Dependency +dep+ from both local (Dir.pwd) and remote (Gem.sources)
  # sources.  Gems are sorted with newer gems prefered over older gems, and
  # local gems prefered over remote gems.
  def find_gems_with_sources(dep)
    gems_and_sources = []

    if @domain == :both or @domain == :local then
      Dir[File.join(Dir.pwd, "#{dep.name}-[0-9]*.gem")].each do |gem_file|
        spec = Gem::Format.from_file_by_path(gem_file).spec
        gems_and_sources << [spec, gem_file] if spec.name == dep.name
      end
    end

    if @domain == :both or @domain == :remote then
      begin
        requirements = dep.version_requirements.requirements.map do |req, ver|
          req
        end

        all = requirements.length > 1 ||
                (requirements.first != ">=" and requirements.first != ">")

        found = Gem::SourceInfoCache.search_with_source dep, true, all

        gems_and_sources.push(*found)

      rescue Gem::RemoteFetcher::FetchError => e
        if Gem.configuration.really_verbose then
          say "Error fetching remote data:\t\t#{e.message}"
          say "Falling back to local-only install"
        end
        @domain = :local
      end
    end

    gems_and_sources.sort_by do |gem, source|
      [gem, source =~ /^http:\/\// ? 0 : 1] # local gems win
    end
  end

  ##
  # Gathers all dependencies necessary for the installation from local and
  # remote sources unless the ignore_dependencies was given.
  def gather_dependencies
    specs = @specs_and_sources.map { |spec,_| spec }

    dependency_list = Gem::DependencyList.new
    dependency_list.add(*specs)

    unless @ignore_dependencies then
      to_do = specs.dup
      seen = {}

      until to_do.empty? do
        spec = to_do.shift
        next if spec.nil? or seen[spec.name]
        seen[spec.name] = true

        spec.dependencies.each do |dep|
          results = find_gems_with_sources(dep).reverse # local gems first

          results.each do |dep_spec, source_uri|
            next if seen[dep_spec.name]
            @specs_and_sources << [dep_spec, source_uri]
            dependency_list.add dep_spec
            to_do.push dep_spec
          end
        end
      end
    end

    @gems_to_install = dependency_list.dependency_order.reverse
  end

  def find_spec_by_name_and_version gem_name, version = Gem::Requirement.default
    spec_and_source = nil

    glob = if File::ALT_SEPARATOR then
             gem_name.gsub File::ALT_SEPARATOR, File::SEPARATOR
           else
             gem_name
           end

    local_gems = Dir["#{glob}*"].sort.reverse

    unless local_gems.empty? then
      local_gems.each do |gem_file|
        next unless gem_file =~ /gem$/
        begin
          spec = Gem::Format.from_file_by_path(gem_file).spec
          spec_and_source = [spec, gem_file]
          break
        rescue SystemCallError, Gem::Package::FormatError
        end
      end
    end

    if spec_and_source.nil? then
      dep = Gem::Dependency.new gem_name, version
      spec_and_sources = find_gems_with_sources(dep).reverse

      spec_and_source = spec_and_sources.find { |spec, source|
        Gem::Platform.match spec.platform
      }
    end

    if spec_and_source.nil? then
      raise Gem::GemNotFoundException,
        "could not find #{gem_name} locally or in a repository"
    end

    @specs_and_sources = [spec_and_source]
  end

  ##
  # Installs the gem and all its dependencies.
  def install dep_or_name, version = Gem::Requirement.default
    if String === dep_or_name then
      find_spec_by_name_and_version dep_or_name, version
    else
      @specs_and_sources = [find_gems_with_sources(dep_or_name).last]
    end

    gather_dependencies

    spec_dir = File.join @install_dir, 'specifications'
    source_index = Gem::SourceIndex.from_gems_in spec_dir

    @gems_to_install.each do |spec|
      last = spec == @gems_to_install.last
      # HACK is this test for full_name acceptable?
      next if source_index.any? { |n,_| n == spec.full_name } and not last

      # TODO: make this sorta_verbose so other users can benefit from it
      say "Installing gem #{spec.full_name}" if Gem.configuration.really_verbose

      _, source_uri = @specs_and_sources.assoc spec
      begin
        local_gem_path = Gem::RemoteFetcher.fetcher.download spec, source_uri,
                                                             @install_dir
      rescue Gem::RemoteFetcher::FetchError
        next if @force
        raise
      end

      inst = Gem::Installer.new local_gem_path,
                                :env_shebang => @env_shebang,
                                :force => @force,
                                :format_executable => @format_executable,
                                :ignore_dependencies => @ignore_dependencies,
                                :install_dir => @install_dir,
                                :security_policy => @security_policy,
                                :wrappers => @wrappers,
                                :bin_dir => @bin_dir

      spec = inst.install

      @installed_gems << spec
    end
  end

end

