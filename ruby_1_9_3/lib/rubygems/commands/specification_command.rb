require 'rubygems/command'
require 'rubygems/local_remote_options'
require 'rubygems/version_option'
require 'rubygems/format'

class Gem::Commands::SpecificationCommand < Gem::Command

  include Gem::LocalRemoteOptions
  include Gem::VersionOption

  def initialize
    Gem.load_yaml

    super 'specification', 'Display gem specification (in yaml)',
          :domain => :local, :version => Gem::Requirement.default,
          :format => :yaml

    add_version_option('examine')
    add_platform_option

    add_option('--all', 'Output specifications for all versions of',
               'the gem') do |value, options|
      options[:all] = true
    end

    add_option('--ruby', 'Output ruby format') do |value, options|
      options[:format] = :ruby
    end

    add_option('--yaml', 'Output RUBY format') do |value, options|
      options[:format] = :yaml
    end

    add_option('--marshal', 'Output Marshal format') do |value, options|
      options[:format] = :marshal
    end

    add_local_remote_options
  end

  def arguments # :nodoc:
    <<-ARGS
GEMFILE       name of gem to show the gemspec for
FIELD         name of gemspec field to show
    ARGS
  end

  def defaults_str # :nodoc:
    "--local --version '#{Gem::Requirement.default}' --yaml"
  end

  def usage # :nodoc:
    "#{program_name} [GEMFILE] [FIELD]"
  end

  def execute
    specs = []
    gem = options[:args].shift

    unless gem then
      raise Gem::CommandLineError,
            "Please specify a gem name or file on the command line"
    end

    case options[:version]
    when String
      req = Gem::Requirement.parse options[:version]
    when Gem::Requirement
      req = options[:version]
    else
      raise Gem::CommandLineError, "Unsupported version type: #{options[:version]}"
    end

    if !req.none? and options[:all]
      alert_error "Specify --all or -v, not both"
      terminate_interaction 1
    end

    if options[:all]
      dep = Gem::Dependency.new gem
    else
      dep = Gem::Dependency.new gem, options[:version]
    end

    field = get_one_optional_argument

    raise Gem::CommandLineError, "--ruby and FIELD are mutually exclusive" if
      field and options[:format] == :ruby

    if local? then
      if File.exist? gem then
        specs << Gem::Format.from_file_by_path(gem).spec rescue nil
      end

      if specs.empty? then
        specs.push(*dep.matching_specs)
      end
    end

    if remote? then
      found = Gem::SpecFetcher.fetcher.fetch dep, true

      if dep.prerelease? or options[:prerelease]
        found += Gem::SpecFetcher.fetcher.fetch dep, false, true, true
      end

      specs.push(*found.map { |spec,| spec })
    end

    if specs.empty? then
      alert_error "Unknown gem '#{gem}'"
      terminate_interaction 1
    end

    unless options[:all] then
      specs = [specs.sort_by { |s| s.version }.last]
    end

    specs.each do |s|
      s = s.send field if field

      say case options[:format]
          when :ruby then s.to_ruby
          when :marshal then Marshal.dump s
          else s.to_yaml
          end

      say "\n"
    end
  end
end
