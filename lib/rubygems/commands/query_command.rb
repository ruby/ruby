require 'rubygems/command'
require 'rubygems/local_remote_options'
require 'rubygems/source_info_cache'
require 'rubygems/version_option'

class Gem::Commands::QueryCommand < Gem::Command

  include Gem::LocalRemoteOptions
  include Gem::VersionOption

  def initialize(name = 'query',
                 summary = 'Query gem information in local or remote repositories')
    super name, summary,
         :name => //, :domain => :local, :details => false, :versions => true,
         :installed => false, :version => Gem::Requirement.default

    add_option('-i', '--[no-]installed',
               'Check for installed gem') do |value, options|
      options[:installed] = value
    end

    add_version_option

    add_option('-n', '--name-matches REGEXP',
               'Name of gem(s) to query on matches the',
               'provided REGEXP') do |value, options|
      options[:name] = /#{value}/i
    end

    add_option('-d', '--[no-]details',
               'Display detailed information of gem(s)') do |value, options|
      options[:details] = value
    end

    add_option(      '--[no-]versions',
               'Display only gem names') do |value, options|
      options[:versions] = value
      options[:details] = false unless value
    end

    add_option('-a', '--all',
               'Display all gem versions') do |value, options|
      options[:all] = value
    end

    add_local_remote_options
  end

  def defaults_str # :nodoc:
    "--local --name-matches // --no-details --versions --no-installed"
  end

  def execute
    exit_code = 0

    name = options[:name]

    if options[:installed] then
      if name.source.empty? then
        alert_error "You must specify a gem name"
        exit_code |= 4
      elsif installed? name.source, options[:version] then
        say "true"
      else
        say "false"
        exit_code |= 1
      end

      raise Gem::SystemExitException, exit_code
    end

    if local? then
      say
      say "*** LOCAL GEMS ***"
      say

      output_query_results Gem.source_index.search(name)
    end

    if remote? then
      say
      say "*** REMOTE GEMS ***"
      say

      all = options[:all]

      begin
        Gem::SourceInfoCache.cache all
      rescue Gem::RemoteFetcher::FetchError
        # no network
      end

      output_query_results Gem::SourceInfoCache.search(name, false, all)
    end
  end

  private

  ##
  # Check if gem +name+ version +version+ is installed.

  def installed?(name, version = Gem::Requirement.default)
    dep = Gem::Dependency.new name, version
    !Gem.source_index.search(dep).empty?
  end

  def output_query_results(gemspecs)
    output = []
    gem_list_with_version = {}

    gemspecs.flatten.each do |gemspec|
      gem_list_with_version[gemspec.name] ||= []
      gem_list_with_version[gemspec.name] << gemspec
    end

    gem_list_with_version = gem_list_with_version.sort_by do |name, spec|
      name.downcase
    end

    gem_list_with_version.each do |gem_name, list_of_matching|
      list_of_matching = list_of_matching.sort_by { |x| x.version.to_ints }.reverse
      seen_versions = {}

      list_of_matching.delete_if do |item|
        if seen_versions[item.version] then
          true
        else
          seen_versions[item.version] = true
          false
        end
      end

      entry = gem_name.dup

      if options[:versions] then
        versions = list_of_matching.map { |s| s.version }.uniq
        entry << " (#{versions.join ', '})"
      end

      entry << "\n" << format_text(list_of_matching[0].summary, 68, 4) if
        options[:details]
      output << entry
    end

    say output.join(options[:details] ? "\n\n" : "\n")
  end

  ##
  # Used for wrapping and indenting text

  def format_text(text, wrap, indent=0)
    result = []
    work = text.dup

    while work.length > wrap
      if work =~ /^(.{0,#{wrap}})[ \n]/o then
        result << $1
        work.slice!(0, $&.length)
      else
        result << work.slice!(0, wrap)
      end
    end

    result << work if work.length.nonzero?
    result.join("\n").gsub(/^/, " " * indent)
  end

end

