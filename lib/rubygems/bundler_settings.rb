# frozen_string_literal: true

require_relative "util"

##
# Reads Bundler's settings without loading Bundler, for the RubyGems commands
# that have to agree with something the user configured for Bundler.
#
# Follows Bundler::Settings: the application config file wins over the
# BUNDLE_<NAME> environment variable, which wins over the user config file,
# and BUNDLE_IGNORE_CONFIG drops both files.

module Gem::BundlerSettings
  ##
  # The configured value of Bundler setting +name+, or nil when it is unset.

  def self.[](name)
    key = key_for name

    value = config_value app_config_file, key
    value = env_value key if value.nil?
    value = config_value user_config_file, key if value.nil?
    value
  end

  ##
  # The value of Bundler setting +name+ from the config files only,
  # application file first.  Callers that read the environment variable ahead
  # of the files pair this with .env.

  def self.from_config_files(name)
    key = key_for name

    value = config_value app_config_file, key
    value.nil? ? config_value(user_config_file, key) : value
  end

  ##
  # The value of Bundler setting +name+ from the environment, or nil when the
  # variable is unset or empty.

  def self.env(name)
    env_value key_for(name)
  end

  ##
  # The gem dependencies file above the working directory, or nil when there
  # is none.  RubyGems recognizes a couple of names Bundler does not, so a
  # directory holding only one of those is where the two disagree.

  def self.gemfile_path
    gemfile = env_value "BUNDLE_GEMFILE"
    return gemfile if gemfile

    Gem::Util.traverse_parents(Dir.pwd) do |directory|
      found = Gem::GEM_DEP_FILES.find {|f| File.file?(f) }

      return File.join(directory, found) if found
    end

    nil
  rescue SystemCallError
    # Dir.pwd raises when the working directory has been deleted, and when
    # an ancestor denies search to the current uid.
    nil
  end

  def self.key_for(name)
    "BUNDLE_#{name.to_s.gsub(".", "__").gsub("-", "___").upcase}"
  end
  private_class_method :key_for

  def self.env_value(key)
    value = ENV[key]

    value unless value.nil? || value.empty?
  end
  private_class_method :env_value

  ##
  # The config file for the application, honoring BUNDLE_APP_CONFIG the way
  # Bundler.app_config_path does: an absolute path is used as given, and a
  # relative one is resolved against the directory holding the Gemfile.

  def self.app_config_file
    return if ignore_config?

    app_config = env_value("BUNDLE_APP_CONFIG") || ".bundle"
    return File.join(app_config, "config") if File.absolute_path?(app_config)

    gemfile = gemfile_path
    File.join(File.dirname(gemfile), app_config, "config") if gemfile
  end
  private_class_method :app_config_file

  def self.user_config_file
    return if ignore_config?

    file = env_value("BUNDLE_CONFIG") || env_value("BUNDLE_USER_CONFIG")
    return file if file

    home = env_value("BUNDLE_USER_HOME")
    return File.join(home, "config") if home

    user_home = Gem.user_home
    File.join(user_home, ".bundle", "config") if user_home && !user_home.empty?
  end
  private_class_method :user_config_file

  def self.ignore_config?
    !ENV["BUNDLE_IGNORE_CONFIG"].nil?
  end
  private_class_method :ignore_config?

  ##
  # A config file that cannot be read or parsed leaves the setting
  # unconfigured rather than aborting the gem command that only wanted to
  # consult it.  The rescue is deliberately broad: Gem::YAMLSerializer signals
  # a bad document with Psych::DisallowedClass, Psych::BadAlias and
  # Psych::SyntaxError, which share no class this method could name, and a
  # reader that only ever returns a value or nil gains nothing from letting a
  # newly added one through.

  def self.config_value(file, key)
    return unless file && File.file?(file)

    require_relative "yaml_serializer"

    config = Gem::YAMLSerializer.load File.read(file)
    # A config file whose top level is not a mapping has no settings in it,
    # and indexing it would read a substring or raise instead of saying so.
    config[key] if config.is_a?(Hash)
  rescue StandardError
    nil
  end
  private_class_method :config_value
end
