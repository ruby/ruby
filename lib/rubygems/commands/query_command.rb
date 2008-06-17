require 'rubygems/command'
require 'rubygems/local_remote_options'
require 'rubygems/spec_fetcher'
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

      specs = Gem.source_index.search name

      spec_tuples = specs.map do |spec|
        [[spec.name, spec.version, spec.original_platform, spec], :local]
      end

      output_query_results spec_tuples
    end

    if remote? then
      say
      say "*** REMOTE GEMS ***"
      say

      all = options[:all]

      dep = Gem::Dependency.new name, Gem::Requirement.default
      begin
        fetcher = Gem::SpecFetcher.fetcher
        spec_tuples = fetcher.find_matching dep, all, false
      rescue Gem::RemoteFetcher::FetchError => e
        raise unless fetcher.warn_legacy e do
          require 'rubygems/source_info_cache'

          dep.name = '' if dep.name == //

          specs = Gem::SourceInfoCache.search_with_source dep, false, all

          spec_tuples = specs.map do |spec, source_uri|
            [[spec.name, spec.version, spec.original_platform, spec],
             source_uri]
          end
        end
      end

      output_query_results spec_tuples
    end
  end

  private

  ##
  # Check if gem +name+ version +version+ is installed.

  def installed?(name, version = Gem::Requirement.default)
    dep = Gem::Dependency.new name, version
    !Gem.source_index.search(dep).empty?
  end

  def output_query_results(spec_tuples)
    output = []
    versions = Hash.new { |h,name| h[name] = [] }

    spec_tuples.each do |spec_tuple, source_uri|
      versions[spec_tuple.first] << [spec_tuple, source_uri]
    end

    versions = versions.sort_by do |(name,_),_|
      name.downcase
    end

    versions.each do |gem_name, matching_tuples|
      matching_tuples = matching_tuples.sort_by do |(name, version,_),_|
        version
      end.reverse

      seen = {}

      matching_tuples.delete_if do |(name, version,_),_|
        if seen[version] then
          true
        else
          seen[version] = true
          false
        end
      end

      entry = gem_name.dup

      if options[:versions] then
        versions = matching_tuples.map { |(name, version,_),_| version }.uniq
        entry << " (#{versions.join ', '})"
      end

      if options[:details] then
        detail_tuple = matching_tuples.first

        spec = if detail_tuple.first.length == 4 then
                 detail_tuple.first.last
               else
                 uri = URI.parse detail_tuple.last
                 Gem::SpecFetcher.fetcher.fetch_spec detail_tuple.first, uri
               end

        entry << "\n"
        authors = "Author#{spec.authors.length > 1 ? 's' : ''}: "
        authors << spec.authors.join(', ')
        entry << format_text(authors, 68, 4)

        if spec.rubyforge_project and not spec.rubyforge_project.empty? then
          rubyforge = "Rubyforge: http://rubyforge.org/projects/#{spec.rubyforge_project}"
          entry << "\n" << format_text(rubyforge, 68, 4)
        end

        if spec.homepage and not spec.homepage.empty? then
          entry << "\n" << format_text("Homepage: #{spec.homepage}", 68, 4)
        end

        if spec.loaded_from then
          if matching_tuples.length == 1 then
            loaded_from = File.dirname File.dirname(spec.loaded_from)
            entry << "\n" << "    Installed at: #{loaded_from}"
          else
            label = 'Installed at'
            matching_tuples.each do |(_,version,_,s),|
              loaded_from = File.dirname File.dirname(s.loaded_from)
              entry << "\n" << "    #{label} (#{version}): #{loaded_from}"
              label = ' ' * label.length
            end
          end
        end

        entry << "\n\n" << format_text(spec.summary, 68, 4)
      end
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

