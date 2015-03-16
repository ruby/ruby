#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems/user_interaction'
require 'rbconfig'

##
# Gem::ConfigFile RubyGems options and gem command options from gemrc.
#
# gemrc is a YAML file that uses strings to match gem command arguments and
# symbols to match RubyGems options.
#
# Gem command arguments use a String key that matches the command name and
# allow you to specify default arguments:
#
#   install: --no-rdoc --no-ri
#   update: --no-rdoc --no-ri
#
# You can use <tt>gem:</tt> to set default arguments for all commands.
#
# RubyGems options use symbol keys.  Valid options are:
#
# +:backtrace+:: See #backtrace
# +:sources+:: Sets Gem::sources
# +:verbose+:: See #verbose
#
# gemrc files may exist in various locations and are read and merged in
# the following order:
#
# - system wide (/etc/gemrc)
# - per user (~/.gemrc)
# - per environment (gemrc files listed in the GEMRC environment variable)

class Gem::ConfigFile

  include Gem::UserInteraction

  DEFAULT_BACKTRACE = false
  DEFAULT_BULK_THRESHOLD = 1000
  DEFAULT_VERBOSITY = true
  DEFAULT_UPDATE_SOURCES = true

  ##
  # For Ruby packagers to set configuration defaults.  Set in
  # rubygems/defaults/operating_system.rb

  OPERATING_SYSTEM_DEFAULTS = {}

  ##
  # For Ruby implementers to set configuration defaults.  Set in
  # rubygems/defaults/#{RUBY_ENGINE}.rb

  PLATFORM_DEFAULTS = {}

  # :stopdoc:

  SYSTEM_CONFIG_PATH =
    begin
      require "etc"
      Etc.sysconfdir
    rescue LoadError, NoMethodError
      begin
        # TODO: remove after we drop 1.8.7 and 1.9.1
        require 'Win32API'

        CSIDL_COMMON_APPDATA = 0x0023
        path = 0.chr * 260
        if RUBY_VERSION > '1.9' then
          SHGetFolderPath = Win32API.new 'shell32', 'SHGetFolderPath', 'PLPLP',
          'L', :stdcall
          SHGetFolderPath.call nil, CSIDL_COMMON_APPDATA, nil, 1, path
        else
          SHGetFolderPath = Win32API.new 'shell32', 'SHGetFolderPath', 'LLLLP',
          'L'
          SHGetFolderPath.call 0, CSIDL_COMMON_APPDATA, 0, 1, path
        end

        path.strip
      rescue LoadError
        RbConfig::CONFIG["sysconfdir"] || "/etc"
      end
    end

  # :startdoc:

  SYSTEM_WIDE_CONFIG_FILE = File.join SYSTEM_CONFIG_PATH, 'gemrc'

  ##
  # List of arguments supplied to the config file object.

  attr_reader :args

  ##
  # Where to look for gems (deprecated)

  attr_accessor :path

  ##
  # Where to install gems (deprecated)

  attr_accessor :home

  ##
  # True if we print backtraces on errors.

  attr_writer :backtrace

  ##
  # Bulk threshold value.  If the number of missing gems are above this
  # threshold value, then a bulk download technique is used.  (deprecated)

  attr_accessor :bulk_threshold

  ##
  # Verbose level of output:
  # * false -- No output
  # * true -- Normal output
  # * :loud -- Extra output

  attr_accessor :verbose

  ##
  # True if we want to update the SourceInfoCache every time, false otherwise

  attr_accessor :update_sources

  ##
  # True if we want to force specification of gem server when pushing a gem

  attr_accessor :disable_default_gem_server

  # openssl verify mode value, used for remote https connection

  attr_reader :ssl_verify_mode

  ##
  # Path name of directory or file of openssl CA certificate, used for remote
  # https connection

  attr_accessor :ssl_ca_cert

  ##
  # Path name of directory or file of openssl client certificate, used for remote https connection with client authentication

  attr_reader :ssl_client_cert

  ##
  # Create the config file object.  +args+ is the list of arguments
  # from the command line.
  #
  # The following command line options are handled early here rather
  # than later at the time most command options are processed.
  #
  # <tt>--config-file</tt>, <tt>--config-file==NAME</tt>::
  #   Obviously these need to be handled by the ConfigFile object to ensure we
  #   get the right config file.
  #
  # <tt>--backtrace</tt>::
  #   Backtrace needs to be turned on early so that errors before normal
  #   option parsing can be properly handled.
  #
  # <tt>--debug</tt>::
  #   Enable Ruby level debug messages.  Handled early for the same reason as
  #   --backtrace.
  #--
  # TODO: parse options upstream, pass in options directly

  def initialize(args)
    @config_file_name = nil
    need_config_file_name = false

    arg_list = []

    args.each do |arg|
      if need_config_file_name then
        @config_file_name = arg
        need_config_file_name = false
      elsif arg =~ /^--config-file=(.*)/ then
        @config_file_name = $1
      elsif arg =~ /^--config-file$/ then
        need_config_file_name = true
      else
        arg_list << arg
      end
    end

    @backtrace = DEFAULT_BACKTRACE
    @bulk_threshold = DEFAULT_BULK_THRESHOLD
    @verbose = DEFAULT_VERBOSITY
    @update_sources = DEFAULT_UPDATE_SOURCES

    operating_system_config = Marshal.load Marshal.dump(OPERATING_SYSTEM_DEFAULTS)
    platform_config = Marshal.load Marshal.dump(PLATFORM_DEFAULTS)
    system_config = load_file SYSTEM_WIDE_CONFIG_FILE
    user_config = load_file config_file_name.dup.untaint
    environment_config = (ENV['GEMRC'] || '').split(/[:;]/).inject({}) do |result, file|
      result.merge load_file file
    end


    @hash = operating_system_config.merge platform_config
    @hash = @hash.merge system_config
    @hash = @hash.merge user_config
    @hash = @hash.merge environment_config

    # HACK these override command-line args, which is bad
    @backtrace                  = @hash[:backtrace]                  if @hash.key? :backtrace
    @bulk_threshold             = @hash[:bulk_threshold]             if @hash.key? :bulk_threshold
    @home                       = @hash[:gemhome]                    if @hash.key? :gemhome
    @path                       = @hash[:gempath]                    if @hash.key? :gempath
    @update_sources             = @hash[:update_sources]             if @hash.key? :update_sources
    @verbose                    = @hash[:verbose]                    if @hash.key? :verbose
    @disable_default_gem_server = @hash[:disable_default_gem_server] if @hash.key? :disable_default_gem_server

    @ssl_verify_mode  = @hash[:ssl_verify_mode]  if @hash.key? :ssl_verify_mode
    @ssl_ca_cert      = @hash[:ssl_ca_cert]      if @hash.key? :ssl_ca_cert
    @ssl_client_cert  = @hash[:ssl_client_cert]  if @hash.key? :ssl_client_cert

    @api_keys         = nil
    @rubygems_api_key = nil

    Gem.sources = @hash[:sources] if @hash.key? :sources
    handle_arguments arg_list
  end

  ##
  # Hash of RubyGems.org and alternate API keys

  def api_keys
    load_api_keys unless @api_keys

    @api_keys
  end

  ##
  # Checks the permissions of the credentials file.  If they are not 0600 an
  # error message is displayed and RubyGems aborts.

  def check_credentials_permissions
    return if Gem.win_platform? # windows doesn't write 0600 as 0600
    return unless File.exist? credentials_path

    existing_permissions = File.stat(credentials_path).mode & 0777

    return if existing_permissions == 0600

    alert_error <<-ERROR
Your gem push credentials file located at:

\t#{credentials_path}

has file permissions of 0#{existing_permissions.to_s 8} but 0600 is required.

To fix this error run:

\tchmod 0600 #{credentials_path}

You should reset your credentials at:

\thttps://rubygems.org/profile/edit

if you believe they were disclosed to a third party.
    ERROR

    terminate_interaction 1
  end

  ##
  # Location of RubyGems.org credentials

  def credentials_path
    File.join Gem.user_home, '.gem', 'credentials'
  end

  def load_api_keys
    check_credentials_permissions

    @api_keys = if File.exist? credentials_path then
                  load_file(credentials_path)
                else
                  @hash
                end

    if @api_keys.key? :rubygems_api_key then
      @rubygems_api_key    = @api_keys[:rubygems_api_key]
      @api_keys[:rubygems] = @api_keys.delete :rubygems_api_key unless
        @api_keys.key? :rubygems
    end
  end

  ##
  # Returns the RubyGems.org API key

  def rubygems_api_key
    load_api_keys unless @rubygems_api_key

    @rubygems_api_key
  end

  ##
  # Sets the RubyGems.org API key to +api_key+

  def rubygems_api_key= api_key
    check_credentials_permissions

    config = load_file(credentials_path).merge(:rubygems_api_key => api_key)

    dirname = File.dirname credentials_path
    Dir.mkdir(dirname) unless File.exist? dirname

    Gem.load_yaml

    permissions = 0600 & (~File.umask)
    File.open(credentials_path, 'w', permissions) do |f|
      f.write config.to_yaml
    end

    @rubygems_api_key = api_key
  end

  YAMLErrors = [ArgumentError]
  YAMLErrors << Psych::SyntaxError if defined?(Psych::SyntaxError)

  def load_file(filename)
    Gem.load_yaml

    return {} unless filename and File.exist? filename

    begin
      content = YAML.load(File.read(filename))
      unless content.kind_of? Hash
        warn "Failed to load #{filename} because it doesn't contain valid YAML hash"
        return {}
      end
      return content
    rescue *YAMLErrors => e
      warn "Failed to load #{filename}, #{e}"
    rescue Errno::EACCES
      warn "Failed to load #{filename} due to permissions problem."
    end

    {}
  end

  # True if the backtrace option has been specified, or debug is on.
  def backtrace
    @backtrace or $DEBUG
  end

  # The name of the configuration file.
  def config_file_name
    @config_file_name || Gem.config_file
  end

  # Delegates to @hash
  def each(&block)
    hash = @hash.dup
    hash.delete :update_sources
    hash.delete :verbose
    hash.delete :backtrace
    hash.delete :bulk_threshold

    yield :update_sources, @update_sources
    yield :verbose, @verbose
    yield :backtrace, @backtrace
    yield :bulk_threshold, @bulk_threshold

    yield 'config_file_name', @config_file_name if @config_file_name

    hash.each(&block)
  end

  # Handle the command arguments.
  def handle_arguments(arg_list)
    @args = []

    arg_list.each do |arg|
      case arg
      when /^--(backtrace|traceback)$/ then
        @backtrace = true
      when /^--debug$/ then
        $DEBUG = true

        warn 'NOTE:  Debugging mode prints all exceptions even when rescued'
      else
        @args << arg
      end
    end
  end

  # Really verbose mode gives you extra output.
  def really_verbose
    case verbose
    when true, false, nil then
      false
    else
      true
    end
  end

  # to_yaml only overwrites things you can't override on the command line.
  def to_yaml # :nodoc:
    yaml_hash = {}
    yaml_hash[:backtrace] = if @hash.key?(:backtrace)
                              @hash[:backtrace]
                            else
                              DEFAULT_BACKTRACE
                            end

    yaml_hash[:bulk_threshold] = if @hash.key?(:bulk_threshold)
                                   @hash[:bulk_threshold]
                                 else
                                   DEFAULT_BULK_THRESHOLD
                                 end

    yaml_hash[:sources] = Gem.sources.to_a

    yaml_hash[:update_sources] = if @hash.key?(:update_sources)
                                   @hash[:update_sources]
                                 else
                                   DEFAULT_UPDATE_SOURCES
                                 end

    yaml_hash[:verbose] = if @hash.key?(:verbose)
                            @hash[:verbose]
                          else
                            DEFAULT_VERBOSITY
                          end

    yaml_hash[:ssl_verify_mode] =
      @hash[:ssl_verify_mode] if @hash.key? :ssl_verify_mode

    yaml_hash[:ssl_ca_cert] =
      @hash[:ssl_ca_cert] if @hash.key? :ssl_ca_cert

    yaml_hash[:ssl_client_cert] =
      @hash[:ssl_client_cert] if @hash.key? :ssl_client_cert

    keys = yaml_hash.keys.map { |key| key.to_s }
    keys << 'debug'
    re = Regexp.union(*keys)

    @hash.each do |key, value|
      key = key.to_s
      next if key =~ re
      yaml_hash[key.to_s] = value
    end

    yaml_hash.to_yaml
  end

  # Writes out this config file, replacing its source.
  def write
    open config_file_name, 'w' do |io|
      io.write to_yaml
    end
  end

  # Return the configuration information for +key+.
  def [](key)
    @hash[key.to_s]
  end

  # Set configuration option +key+ to +value+.
  def []=(key, value)
    @hash[key.to_s] = value
  end

  def ==(other) # :nodoc:
    self.class === other and
      @backtrace == other.backtrace and
      @bulk_threshold == other.bulk_threshold and
      @verbose == other.verbose and
      @update_sources == other.update_sources and
      @hash == other.hash
  end

  attr_reader :hash
  protected :hash
end
