# frozen_string_literal: true
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'uri'
require 'rubygems'

##
# Mixin methods for local and remote Gem::Command options.

module Gem::LocalRemoteOptions

  ##
  # Allows OptionParser to handle HTTP URIs.

  def accept_uri_http
    OptionParser.accept URI::HTTP do |value|
      begin
        uri = URI.parse value
      rescue URI::InvalidURIError
        raise OptionParser::InvalidArgument, value
      end

      valid_uri_schemes = ["http", "https", "file", "s3"]
      unless valid_uri_schemes.include?(uri.scheme)
        msg = "Invalid uri scheme for #{value}\nPreface URLs with one of #{valid_uri_schemes.map{|s| "#{s}://"}}"
        raise ArgumentError, msg
      end

      value
    end
  end

  ##
  # Add local/remote options to the command line parser.

  def add_local_remote_options
    add_option(:"Local/Remote", '-l', '--local',
               'Restrict operations to the LOCAL domain') do |value, options|
      options[:domain] = :local
    end

    add_option(:"Local/Remote", '-r', '--remote',
      'Restrict operations to the REMOTE domain') do |value, options|
      options[:domain] = :remote
    end

    add_option(:"Local/Remote", '-b', '--both',
               'Allow LOCAL and REMOTE operations') do |value, options|
      options[:domain] = :both
    end

    add_bulk_threshold_option
    add_clear_sources_option
    add_source_option
    add_proxy_option
    add_update_sources_option
  end

  ##
  # Add the --bulk-threshold option

  def add_bulk_threshold_option
    add_option(:"Local/Remote", '-B', '--bulk-threshold COUNT',
               "Threshold for switching to bulk",
               "synchronization (default #{Gem.configuration.bulk_threshold})") do
      |value, options|
      Gem.configuration.bulk_threshold = value.to_i
    end
  end

  ##
  # Add the --clear-sources option

  def add_clear_sources_option
    add_option(:"Local/Remote", '--clear-sources',
               'Clear the gem sources') do |value, options|

      Gem.sources = nil
      options[:sources_cleared] = true
    end
  end

  ##
  # Add the --http-proxy option

  def add_proxy_option
    accept_uri_http

    add_option(:"Local/Remote", '-p', '--[no-]http-proxy [URL]', URI::HTTP,
               'Use HTTP proxy for remote operations') do |value, options|
      options[:http_proxy] = (value == false) ? :no_proxy : value
      Gem.configuration[:http_proxy] = options[:http_proxy]
    end
  end

  ##
  # Add the --source option

  def add_source_option
    accept_uri_http

    add_option(:"Local/Remote", '-s', '--source URL', URI::HTTP,
               'Append URL to list of remote gem sources') do |source, options|

      source << '/' if source !~ /\/\z/

      if options.delete :sources_cleared
        Gem.sources = [source]
      else
        Gem.sources << source unless Gem.sources.include?(source)
      end
    end
  end

  ##
  # Add the --update-sources option

  def add_update_sources_option
    add_option(:Deprecated, '-u', '--[no-]update-sources',
               'Update local source cache') do |value, options|
      Gem.configuration.update_sources = value
    end
  end

  ##
  # Is fetching of local and remote information enabled?

  def both?
    options[:domain] == :both
  end

  ##
  # Is local fetching enabled?

  def local?
    options[:domain] == :local || options[:domain] == :both
  end

  ##
  # Is remote fetching enabled?

  def remote?
    options[:domain] == :remote || options[:domain] == :both
  end

end
