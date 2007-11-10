require 'yaml'
require 'rubygems/command'
require 'rubygems/local_remote_options'
require 'rubygems/version_option'
require 'rubygems/source_info_cache'

class Gem::Commands::SpecificationCommand < Gem::Command

  include Gem::LocalRemoteOptions
  include Gem::VersionOption

  def initialize
    super 'specification', 'Display gem specification (in yaml)',
          :domain => :local, :version => Gem::Requirement.default

    add_version_option('examine')
    add_platform_option

    add_option('--all', 'Output specifications for all versions of',
               'the gem') do |value, options|
      options[:all] = true
    end

    add_local_remote_options
  end

  def arguments # :nodoc:
    "GEMFILE       name of gem to show the gemspec for"
  end

  def defaults_str # :nodoc:
    "--local --version '#{Gem::Requirement.default}'"
  end

  def usage # :nodoc:
    "#{program_name} [GEMFILE]"
  end

  def execute
    specs = []
    gem = get_one_gem_name

    if local? then
      source_index = Gem::SourceIndex.from_installed_gems
      specs.push(*source_index.search(/\A#{gem}\z/, options[:version]))
    end

    if remote? then
      alert_warning "Remote information is not complete\n\n"

      Gem::SourceInfoCache.cache_data.each do |_,sice|
        specs.push(*sice.source_index.search(gem, options[:version]))
      end
    end

    if specs.empty? then
      alert_error "Unknown gem '#{gem}'"
      terminate_interaction 1
    end

    output = lambda { |spec| say spec.to_yaml; say "\n" }

    if options[:all] then
      specs.each(&output)
    else
      spec = specs.sort_by { |spec| spec.version }.last
      output[spec]
    end
  end

end

