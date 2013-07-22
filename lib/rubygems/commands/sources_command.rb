require 'rubygems/command'
require 'rubygems/remote_fetcher'
require 'rubygems/spec_fetcher'
require 'rubygems/local_remote_options'

class Gem::Commands::SourcesCommand < Gem::Command

  include Gem::LocalRemoteOptions

  def initialize
    require 'fileutils'

    super 'sources',
          'Manage the sources and cache file RubyGems uses to search for gems'

    add_option '-a', '--add SOURCE_URI', 'Add source' do |value, options|
      options[:add] = value
    end

    add_option '-l', '--list', 'List sources' do |value, options|
      options[:list] = value
    end

    add_option '-r', '--remove SOURCE_URI', 'Remove source' do |value, options|
      options[:remove] = value
    end

    add_option '-c', '--clear-all',
               'Remove all sources (clear the cache)' do |value, options|
      options[:clear_all] = value
    end

    add_option '-u', '--update', 'Update source cache' do |value, options|
      options[:update] = value
    end

    add_proxy_option
  end

  def add_source source_uri # :nodoc:
    check_rubygems_https source_uri

    source = Gem::Source.new source_uri

    begin
      if Gem.sources.include? source_uri then
        say "source #{source_uri} already present in the cache"
      else
        source.load_specs :released
        Gem.sources << source
        Gem.configuration.write

        say "#{source_uri} added to sources"
      end
    rescue URI::Error, ArgumentError
      say "#{source_uri} is not a URI"
      terminate_interaction 1
    rescue Gem::RemoteFetcher::FetchError => e
      say "Error fetching #{source_uri}:\n\t#{e.message}"
      terminate_interaction 1
    end
  end

  def check_rubygems_https source_uri # :nodoc:
    uri = URI source_uri

    if uri.scheme and uri.scheme.downcase == 'http' and
       uri.host.downcase == 'rubygems.org' then
      question = <<-QUESTION.chomp
https://rubygems.org is recommended for security over #{uri}

Do you want to add this insecure source?
      QUESTION

      terminate_interaction 1 unless ask_yes_no question
    end
  end

  def clear_all # :nodoc:
    path = Gem.spec_cache_dir
    FileUtils.rm_rf path

    unless File.exist? path then
      say "*** Removed specs cache ***"
    else
      unless File.writable? path then
        say "*** Unable to remove source cache (write protected) ***"
      else
        say "*** Unable to remove source cache ***"
      end

      terminate_interaction 1
    end
  end

  def defaults_str # :nodoc:
    '--list'
  end

  def list # :nodoc:
    say "*** CURRENT SOURCES ***"
    say

    Gem.sources.each do |src|
      say src
    end
  end

  def list? # :nodoc:
    !(options[:list] ||
      options[:add] ||
      options[:clear_all] ||
      options[:remove] ||
      options[:update])
  end

  def execute
    clear_all if options[:clear_all]

    source_uri = options[:add]
    add_source source_uri if source_uri

    source_uri = options[:remove]
    remove_source source_uri if source_uri

    update if options[:update]

    list if list?
  end

  def remove_source source_uri # :nodoc:
    unless Gem.sources.include? source_uri then
      say "source #{source_uri} not present in cache"
    else
      Gem.sources.delete source_uri
      Gem.configuration.write

      say "#{source_uri} removed from sources"
    end
  end

  def update # :nodoc:
    Gem.sources.each_source do |src|
      src.load_specs :released
      src.load_specs :latest
    end

    say "source cache successfully updated"
  end

  def remove_cache_file desc, path # :nodoc:
    FileUtils.rm_rf path

    if not File.exist?(path) then
      say "*** Removed #{desc} source cache ***"
    elsif not File.writable?(path) then
      say "*** Unable to remove #{desc} source cache (write protected) ***"
    else
      say "*** Unable to remove #{desc} source cache ***"
    end
  end

end

