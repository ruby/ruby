require 'rubygems/command'
require 'rubygems/local_remote_options'
require 'rubygems/version_option'
require 'rubygems/source_info_cache'

class Gem::Commands::DependencyCommand < Gem::Command

  include Gem::LocalRemoteOptions
  include Gem::VersionOption

  def initialize
    super 'dependency',
          'Show the dependencies of an installed gem',
          :version => Gem::Requirement.default, :domain => :local

    add_version_option
    add_platform_option
    add_prerelease_option

    add_option('-R', '--[no-]reverse-dependencies',
               'Include reverse dependencies in the output') do
      |value, options|
      options[:reverse_dependencies] = value
    end

    add_option('-p', '--pipe',
               "Pipe Format (name --version ver)") do |value, options|
      options[:pipe_format] = value
    end

    add_local_remote_options
  end

  def arguments # :nodoc:
    "GEMNAME       name of gem to show dependencies for"
  end

  def defaults_str # :nodoc:
    "--local --version '#{Gem::Requirement.default}' --no-reverse-dependencies"
  end

  def usage # :nodoc:
    "#{program_name} GEMNAME"
  end

  def execute
    options[:args] << '' if options[:args].empty?
    specs = {}

    source_indexes = Hash.new do |h, source_uri|
      h[source_uri] = Gem::SourceIndex.new
    end

    pattern = if options[:args].length == 1 and
                 options[:args].first =~ /\A\/(.*)\/(i)?\z/m then
                flags = $2 ? Regexp::IGNORECASE : nil
                Regexp.new $1, flags
              else
                /\A#{Regexp.union(*options[:args])}/
              end

    dependency = Gem::Dependency.new pattern, options[:version]
    dependency.prerelease = options[:prerelease]

    if options[:reverse_dependencies] and remote? and not local? then
      alert_error 'Only reverse dependencies for local gems are supported.'
      terminate_interaction 1
    end

    if local? then
      Gem.source_index.search(dependency).each do |spec|
        source_indexes[:local].add_spec spec
      end
    end

    if remote? and not options[:reverse_dependencies] then
      fetcher = Gem::SpecFetcher.fetcher

      begin
        specs_and_sources = fetcher.find_matching(dependency, false, true,
                                                  dependency.prerelease?)

        specs_and_sources.each do |spec_tuple, source_uri|
          spec = fetcher.fetch_spec spec_tuple, URI.parse(source_uri)

          source_indexes[source_uri].add_spec spec
        end
      rescue Gem::RemoteFetcher::FetchError => e
        raise unless fetcher.warn_legacy e do
          require 'rubygems/source_info_cache'

          specs = Gem::SourceInfoCache.search_with_source dependency, false

          specs.each do |spec, source_uri|
            source_indexes[source_uri].add_spec spec
          end
        end
      end
    end

    if source_indexes.empty? then
      patterns = options[:args].join ','
      say "No gems found matching #{patterns} (#{options[:version]})" if
        Gem.configuration.verbose

      terminate_interaction 1
    end

    specs = {}

    source_indexes.values.each do |source_index|
      source_index.gems.each do |name, spec|
        specs[spec.full_name] = [source_index, spec]
      end
    end

    reverse = Hash.new { |h, k| h[k] = [] }

    if options[:reverse_dependencies] then
      specs.values.each do |_, spec|
        reverse[spec.full_name] = find_reverse_dependencies spec
      end
    end

    if options[:pipe_format] then
      specs.values.sort_by { |_, spec| spec }.each do |_, spec|
        unless spec.dependencies.empty?
          spec.dependencies.sort_by { |dep| dep.name }.each do |dep|
            say "#{dep.name} --version '#{dep.requirement}'"
          end
        end
      end
    else
      response = ''

      specs.values.sort_by { |_, spec| spec }.each do |_, spec|
        response << print_dependencies(spec)
        unless reverse[spec.full_name].empty? then
          response << "  Used by\n"
          reverse[spec.full_name].each do |sp, dep|
            response << "    #{sp} (#{dep})\n"
          end
        end
        response << "\n"
      end

      say response
    end
  end

  def print_dependencies(spec, level = 0)
    response = ''
    response << '  ' * level + "Gem #{spec.full_name}\n"
    unless spec.dependencies.empty? then
      spec.dependencies.sort_by { |dep| dep.name }.each do |dep|
        response << '  ' * level + "  #{dep}\n"
      end
    end
    response
  end

  ##
  # Returns an Array of [specification, dep] that are satisfied by +spec+.

  def find_reverse_dependencies(spec)
    result = []

    Gem.source_index.each do |name, sp|
      sp.dependencies.each do |dep|
        dep = Gem::Dependency.new(*dep) unless Gem::Dependency === dep

        if spec.name == dep.name and
           dep.requirement.satisfied_by?(spec.version) then
          result << [sp.full_name, dep]
        end
      end
    end

    result
  end

  def find_gems(name, source_index)
    specs = {}

    spec_list = source_index.search name, options[:version]

    spec_list.each do |spec|
      specs[spec.full_name] = [source_index, spec]
    end

    specs
  end

end

