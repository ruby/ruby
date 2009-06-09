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

    dep = Gem::Dependency.new gem, options[:version]

    field = get_one_optional_argument

    if field then
      field = field.intern

      if options[:format] == :ruby then
        raise Gem::CommandLineError, "--ruby and FIELD are mutually exclusive"
      end

      unless Gem::Specification.attribute_names.include? field then
        raise Gem::CommandLineError,
              "no field %p on Gem::Specification" % field.to_s
      end
    end

    if local? then
      if File.exist? gem then
        specs << Gem::Format.from_file_by_path(gem).spec rescue nil
      end

      if specs.empty? then
        specs.push(*Gem.source_index.search(dep))
      end
    end

    if remote? then
      found = Gem::SpecFetcher.fetcher.fetch dep

      specs.push(*found.map { |spec,| spec })
    end

    if specs.empty? then
      alert_error "Unknown gem '#{gem}'"
      terminate_interaction 1
    end

    output = lambda do |s|
      s = s.send field if field

      say case options[:format]
          when :ruby then s.to_ruby
          when :marshal then Marshal.dump s
          else s.to_yaml
          end

      say "\n"
    end

    if options[:all] then
      specs.each(&output)
    else
      spec = specs.sort_by { |s| s.version }.last
      output[spec]
    end
  end

end

