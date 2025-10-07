# frozen_string_literal: true

require_relative "../command"
require_relative "../remote_fetcher"
require_relative "../spec_fetcher"
require_relative "../local_remote_options"

class Gem::Commands::SourcesCommand < Gem::Command
  include Gem::LocalRemoteOptions

  def initialize
    require "fileutils"

    super "sources",
          "Manage the sources and cache file RubyGems uses to search for gems"

    add_option "-a", "--add SOURCE_URI", "Add source" do |value, options|
      options[:add] = value
    end

    add_option "--append SOURCE_URI", "Append source (can be used multiple times)" do |value, options|
      options[:append] = value
    end

    add_option "-p", "--prepend SOURCE_URI", "Prepend source (can be used multiple times)" do |value, options|
      options[:prepend] = value
    end

    add_option "-l", "--list", "List sources" do |value, options|
      options[:list] = value
    end

    add_option "-r", "--remove SOURCE_URI", "Remove source" do |value, options|
      options[:remove] = value
    end

    add_option "-c", "--clear-all", "Remove all sources (clear the cache)" do |value, options|
      options[:clear_all] = value
    end

    add_option "-u", "--update", "Update source cache" do |value, options|
      options[:update] = value
    end

    add_option "-f", "--[no-]force", "Do not show any confirmation prompts and behave as if 'yes' was always answered" do |value, options|
      options[:force] = value
    end

    add_proxy_option
  end

  def add_source(source_uri) # :nodoc:
    check_rubygems_https source_uri

    source = Gem::Source.new source_uri

    check_typo_squatting(source)

    begin
      if Gem.sources.include? source
        say "source #{source_uri} already present in the cache"
      else
        source.load_specs :released
        Gem.sources << source
        Gem.configuration.write

        say "#{source_uri} added to sources"
      end
    rescue Gem::URI::Error, ArgumentError
      say "#{source_uri} is not a URI"
      terminate_interaction 1
    rescue Gem::RemoteFetcher::FetchError => e
      say "Error fetching #{Gem::Uri.redact(source.uri)}:\n\t#{e.message}"
      terminate_interaction 1
    end
  end

  def append_source(source_uri) # :nodoc:
    check_rubygems_https source_uri

    source = Gem::Source.new source_uri

    check_typo_squatting(source)

    begin
      source.load_specs :released
      was_present = Gem.sources.include?(source)
      Gem.sources.append source
      Gem.configuration.write

      if was_present
        say "#{source_uri} moved to end of sources"
      else
        say "#{source_uri} added to sources"
      end
    rescue Gem::URI::Error, ArgumentError
      say "#{source_uri} is not a URI"
      terminate_interaction 1
    rescue Gem::RemoteFetcher::FetchError => e
      say "Error fetching #{Gem::Uri.redact(source.uri)}:\n\t#{e.message}"
      terminate_interaction 1
    end
  end

  def prepend_source(source_uri) # :nodoc:
    check_rubygems_https source_uri

    source = Gem::Source.new source_uri

    check_typo_squatting(source)

    begin
      source.load_specs :released
      was_present = Gem.sources.include?(source)
      Gem.sources.prepend source
      Gem.configuration.write

      if was_present
        say "#{source_uri} moved to top of sources"
      else
        say "#{source_uri} added to sources"
      end
    rescue Gem::URI::Error, ArgumentError
      say "#{source_uri} is not a URI"
      terminate_interaction 1
    rescue Gem::RemoteFetcher::FetchError => e
      say "Error fetching #{Gem::Uri.redact(source.uri)}:\n\t#{e.message}"
      terminate_interaction 1
    end
  end

  def check_typo_squatting(source)
    if source.typo_squatting?("rubygems.org")
      question = <<-QUESTION.chomp
#{source.uri} is too similar to https://rubygems.org

Do you want to add this source?
      QUESTION

      terminate_interaction 1 unless options[:force] || ask_yes_no(question)
    end
  end

  def check_rubygems_https(source_uri) # :nodoc:
    uri = Gem::URI source_uri

    if uri.scheme && uri.scheme.casecmp("http").zero? &&
       uri.host.casecmp("rubygems.org").zero?
      question = <<-QUESTION.chomp
https://rubygems.org is recommended for security over #{uri}

Do you want to add this insecure source?
      QUESTION

      terminate_interaction 1 unless options[:force] || ask_yes_no(question)
    end
  end

  def clear_all # :nodoc:
    path = Gem.spec_cache_dir
    FileUtils.rm_rf path

    if File.exist? path
      if File.writable? path
        say "*** Unable to remove source cache ***"
      else
        say "*** Unable to remove source cache (write protected) ***"
      end

      terminate_interaction 1
    else
      say "*** Removed specs cache ***"
    end
  end

  def defaults_str # :nodoc:
    "--list"
  end

  def description # :nodoc:
    <<-EOF
RubyGems fetches gems from the sources you have configured (stored in your
~/.gemrc).

The default source is https://rubygems.org, but you may have other sources
configured.  This guide will help you update your sources or configure
yourself to use your own gem server.

Without any arguments the sources lists your currently configured sources:

  $ gem sources
  *** NO CONFIGURED SOURCES, DEFAULT SOURCES LISTED BELOW ***

  https://rubygems.org

This may list multiple sources or non-rubygems sources.  You probably
configured them before or have an old `~/.gemrc`.  If you have sources you
do not recognize you should remove them.

RubyGems has been configured to serve gems via the following URLs through
its history:

* http://gems.rubyforge.org (RubyGems 1.3.5 and earlier)
* http://rubygems.org       (RubyGems 1.3.6 through 1.8.30, and 2.0.0)
* https://rubygems.org      (RubyGems 2.0.1 and newer)

Since all of these sources point to the same set of gems you only need one
of them in your list.  https://rubygems.org is recommended as it brings the
protections of an SSL connection to gem downloads.

To add a private gem source use the --prepend argument to insert it before
the default source. This is usually the best place for private gem sources:

    $ gem sources --prepend https://my.private.source
    https://my.private.source added to sources

RubyGems will check to see if gems can be installed from the source given
before it is added.

To add or move a source after all other sources, use --append:

    $ gem sources --append https://rubygems.org
    https://rubygems.org moved to end of sources

To remove a source use the --remove argument:

    $ gem sources --remove https://my.private.source/
    https://my.private.source/ removed from sources

    EOF
  end

  def list # :nodoc:
    if configured_sources
      header = "*** CURRENT SOURCES ***"
      list = configured_sources
    else
      header = "*** NO CONFIGURED SOURCES, DEFAULT SOURCES LISTED BELOW ***"
      list = Gem.sources
    end

    say header
    say

    list.each do |src|
      say src
    end
  end

  def list? # :nodoc:
    !(options[:add] ||
      options[:prepend] ||
      options[:append] ||
      options[:clear_all] ||
      options[:remove] ||
      options[:update])
  end

  def execute
    clear_all if options[:clear_all]

    add_source options[:add] if options[:add]

    prepend_source options[:prepend] if options[:prepend]

    append_source options[:append] if options[:append]

    remove_source options[:remove] if options[:remove]

    update if options[:update]

    list if list?
  end

  def remove_source(source_uri) # :nodoc:
    source = Gem::Source.new source_uri

    if configured_sources&.include? source
      Gem.sources.delete source
      Gem.configuration.write

      if default_sources.include?(source) && configured_sources.one?
        alert_warning "Removing a default source when it is the only source has no effect. Add a different source to #{config_file_name} if you want to stop using it as a source."
      else
        say "#{source_uri} removed from sources"
      end
    elsif configured_sources
      say "source #{source_uri} cannot be removed because it's not present in #{config_file_name}"
    else
      say "source #{source_uri} cannot be removed because there are no configured sources in #{config_file_name}"
    end
  end

  def update # :nodoc:
    Gem.sources.each_source do |src|
      src.load_specs :released
      src.load_specs :latest
    end

    say "source cache successfully updated"
  end

  def remove_cache_file(desc, path) # :nodoc:
    FileUtils.rm_rf path

    if !File.exist?(path)
      say "*** Removed #{desc} source cache ***"
    elsif !File.writable?(path)
      say "*** Unable to remove #{desc} source cache (write protected) ***"
    else
      say "*** Unable to remove #{desc} source cache ***"
    end
  end

  private

  def default_sources
    Gem::SourceList.from(Gem.default_sources)
  end

  def configured_sources
    return @configured_sources if defined?(@configured_sources)

    configuration_sources = Gem.configuration.sources
    @configured_sources = Gem::SourceList.from(configuration_sources) if configuration_sources
  end

  def config_file_name
    Gem.configuration.config_file_name
  end
end
