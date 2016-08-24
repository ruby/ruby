# frozen_string_literal: true
require 'rubygems/command'
require 'rubygems/local_remote_options'
require 'rubygems/spec_fetcher'
require 'rubygems/version_option'
require 'rubygems/text'

class Gem::Commands::QueryCommand < Gem::Command

  include Gem::Text
  include Gem::LocalRemoteOptions
  include Gem::VersionOption

  def initialize(name = 'query',
                 summary = 'Query gem information in local or remote repositories')
    super name, summary,
         :name => //, :domain => :local, :details => false, :versions => true,
         :installed => nil, :version => Gem::Requirement.default

    add_option('-i', '--[no-]installed',
               'Check for installed gem') do |value, options|
      options[:installed] = value
    end

    add_option('-I', 'Equivalent to --no-installed') do |value, options|
      options[:installed] = false
    end

    add_version_option command, "for use with --installed"

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

    add_option('-e', '--exact',
               'Name of gem(s) to query on matches the',
               'provided STRING') do |value, options|
      options[:exact] = value
    end

    add_option(      '--[no-]prerelease',
               'Display prerelease versions') do |value, options|
      options[:prerelease] = value
    end

    add_local_remote_options
  end

  def defaults_str # :nodoc:
    "--local --name-matches // --no-details --versions --no-installed"
  end

  def description # :nodoc:
    <<-EOF
The query command is the basis for the list and search commands.

You should really use the list and search commands instead.  This command
is too hard to use.
    EOF
  end

  def execute
    exit_code = 0
    if options[:args].to_a.empty? and options[:name].source.empty?
      name = options[:name]
      no_name = true
    elsif !options[:name].source.empty?
      name = Array(options[:name])
    else
      args = options[:args].to_a
      name = options[:exact] ? args : args.map{|arg| /#{arg}/i }
    end

    prerelease = options[:prerelease]

    unless options[:installed].nil? then
      if no_name then
        alert_error "You must specify a gem name"
        exit_code |= 4
      elsif name.count > 1
        alert_error "You must specify only ONE gem!"
        exit_code |= 4
      else
        installed = installed? name.first, options[:version]
        installed = !installed unless options[:installed]

        if installed then
          say "true"
        else
          say "false"
          exit_code |= 1
        end
      end

      terminate_interaction exit_code
    end

    names = Array(name)
    names.each { |n| show_gems n, prerelease }
  end

  private

  def display_header type
    if (ui.outs.tty? and Gem.configuration.verbose) or both? then
      say
      say "*** #{type} GEMS ***"
      say
    end
  end

  #Guts of original execute
  def show_gems name, prerelease
    req = Gem::Requirement.default
    # TODO: deprecate for real
    dep = Gem::Deprecate.skip_during { Gem::Dependency.new name, req }
    dep.prerelease = prerelease

    if local? then
      if prerelease and not both? then
        alert_warning "prereleases are always shown locally"
      end

      display_header 'LOCAL'

      specs = Gem::Specification.find_all { |s|
        s.name =~ name and req =~ s.version
      }

      spec_tuples = specs.map do |spec|
        [spec.name_tuple, spec]
      end

      output_query_results spec_tuples
    end

    if remote? then
      display_header 'REMOTE'

      fetcher = Gem::SpecFetcher.fetcher

      type = if options[:all]
               if options[:prerelease]
                 :complete
               else
                 :released
               end
             elsif options[:prerelease]
               :prerelease
             else
               :latest
             end

      if name.respond_to?(:source) && name.source.empty?
        spec_tuples = fetcher.detect(type) { true }
      else
        spec_tuples = fetcher.detect(type) do |name_tuple|
          name === name_tuple.name
        end
      end

      output_query_results spec_tuples
    end
  end

  ##
  # Check if gem +name+ version +version+ is installed.

  def installed?(name, req = Gem::Requirement.default)
    Gem::Specification.any? { |s| s.name =~ name and req =~ s.version }
  end

  def output_query_results(spec_tuples)
    output = []
    versions = Hash.new { |h,name| h[name] = [] }

    spec_tuples.each do |spec_tuple, source|
      versions[spec_tuple.name] << [spec_tuple, source]
    end

    versions = versions.sort_by do |(n,_),_|
      n.downcase
    end

    output_versions output, versions

    say output.join(options[:details] ? "\n\n" : "\n")
  end

  def output_versions output, versions
    versions.each do |gem_name, matching_tuples|
      matching_tuples = matching_tuples.sort_by { |n,_| n.version }.reverse

      platforms = Hash.new { |h,version| h[version] = [] }

      matching_tuples.each do |n, _|
        platforms[n.version] << n.platform if n.platform
      end

      seen = {}

      matching_tuples.delete_if do |n,_|
        if seen[n.version] then
          true
        else
          seen[n.version] = true
          false
        end
      end

      output << make_entry(matching_tuples, platforms)
    end
  end

  def entry_details entry, detail_tuple, specs, platforms
    return unless options[:details]

    name_tuple, spec = detail_tuple

    spec = spec.fetch_spec name_tuple if spec.respond_to? :fetch_spec

    entry << "\n"

    spec_platforms   entry, platforms
    spec_authors     entry, spec
    spec_homepage    entry, spec
    spec_license     entry, spec
    spec_loaded_from entry, spec, specs
    spec_summary     entry, spec
  end

  def entry_versions entry, name_tuples, platforms
    return unless options[:versions]

    list =
      if platforms.empty? or options[:details] then
        name_tuples.map { |n| n.version }.uniq
      else
        platforms.sort.reverse.map do |version, pls|
          if pls == [Gem::Platform::RUBY] then
            version
          else
            ruby = pls.delete Gem::Platform::RUBY
            platform_list = [ruby, *pls.sort].compact
            "#{version} #{platform_list.join ' '}"
          end
        end
      end

    entry << " (#{list.join ', '})"
  end

  def make_entry entry_tuples, platforms
    detail_tuple = entry_tuples.first

    name_tuples, specs = entry_tuples.flatten.partition do |item|
      Gem::NameTuple === item
    end

    entry = [name_tuples.first.name]

    entry_versions entry, name_tuples, platforms
    entry_details  entry, detail_tuple, specs, platforms

    entry.join
  end

  def spec_authors entry, spec
    authors = "Author#{spec.authors.length > 1 ? 's' : ''}: ".dup
    authors << spec.authors.join(', ')
    entry << format_text(authors, 68, 4)
  end

  def spec_homepage entry, spec
    return if spec.homepage.nil? or spec.homepage.empty?

    entry << "\n" << format_text("Homepage: #{spec.homepage}", 68, 4)
  end

  def spec_license entry, spec
    return if spec.license.nil? or spec.license.empty?

    licenses = "License#{spec.licenses.length > 1 ? 's' : ''}: ".dup
    licenses << spec.licenses.join(', ')
    entry << "\n" << format_text(licenses, 68, 4)
  end

  def spec_loaded_from entry, spec, specs
    return unless spec.loaded_from

    if specs.length == 1 then
      default = spec.default_gem? ? ' (default)' : nil
      entry << "\n" << "    Installed at#{default}: #{spec.base_dir}"
    else
      label = 'Installed at'
      specs.each do |s|
        version = s.version.to_s
        version << ', default' if s.default_gem?
        entry << "\n" << "    #{label} (#{version}): #{s.base_dir}"
        label = ' ' * label.length
      end
    end
  end

  def spec_platforms entry, platforms
    non_ruby = platforms.any? do |_, pls|
      pls.any? { |pl| pl != Gem::Platform::RUBY }
    end

    return unless non_ruby

    if platforms.length == 1 then
      title = platforms.values.length == 1 ? 'Platform' : 'Platforms'
      entry << "    #{title}: #{platforms.values.sort.join ', '}\n"
    else
      entry << "    Platforms:\n"
      platforms.sort_by do |version,|
        version
      end.each do |version, pls|
        label = "        #{version}: "
        data = format_text pls.sort.join(', '), 68, label.length
        data[0, label.length] = label
        entry << data << "\n"
      end
    end
  end

  def spec_summary entry, spec
    entry << "\n\n" << format_text(spec.summary, 68, 4)
  end

end
