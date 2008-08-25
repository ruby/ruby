require 'yaml'
require 'rubygems/command'
require 'rubygems/local_remote_options'
require 'rubygems/version_option'
require 'rubygems/source_info_cache'
require 'rubygems/format'

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
      if File.exist? gem then
        specs << Gem::Format.from_file_by_path(gem).spec rescue nil
      end

      if specs.empty? then
        specs.push(*Gem.source_index.search(/\A#{gem}\z/, options[:version]))
      end
    end

    if remote? then
      dep = Gem::Dependency.new gem, options[:version]
      found = Gem::SpecFetcher.fetcher.fetch dep

      specs.push(*found.map { |spec,| spec })
    end

    if specs.empty? then
      alert_error "Unknown gem '#{gem}'"
      terminate_interaction 1
    end

    output = lambda { |s| say s.to_yaml; say "\n" }

    if options[:all] then
      specs.each(&output)
    else
      spec = specs.sort_by { |s| s.version }.last
      output[spec]
    end
  end

end

