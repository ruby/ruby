# frozen_string_literal: true

require_relative "bundler_settings"

module Gem::BundlerVersionFinder
  def self.bundler_version
    bcv = bundle_config_version
    return if bcv == "system"

    v = ENV["BUNDLER_VERSION"]
    v = nil if v&.empty?

    v ||= bundle_update_bundler_version
    return if v == true

    v ||= bcv unless bcv == "lockfile"

    v ||= lockfile_version
    return unless v

    # A config file is arbitrary YAML, so BUNDLE_VERSION can be a date, a
    # mapping, or anything else the parser makes of an unquoted scalar. None
    # of those name a version, and refusing to prioritize is better than
    # raising out of every command that resolves bundler by name.
    return unless Gem::Version.correct?(v)

    Gem::Version.new(v)
  end

  def self.prioritize!(specs)
    exact_match_index = specs.find_index {|spec| spec.version == bundler_version }
    return unless exact_match_index

    specs.unshift(specs.delete_at(exact_match_index))
  end

  def self.bundle_update_bundler_version
    return unless ["bundle", "bundler"].include? File.basename($0)
    return unless "update".start_with?(ARGV.first || " ")
    bundler_version = nil
    update_index = nil
    ARGV.each_with_index do |a, i|
      if update_index && update_index.succ == i && a =~ Gem::Version::ANCHORED_VERSION_PATTERN
        bundler_version = a
      end
      next unless a =~ /\A--bundler(?:[= ](#{Gem::Version::VERSION_PATTERN}))?\z/
      bundler_version = $1 || true
      update_index = i
    end
    bundler_version
  end
  private_class_method :bundle_update_bundler_version

  def self.lockfile_version
    return unless contents = lockfile_contents
    regexp = /\n\nBUNDLED WITH\n\s{2,}(#{Gem::Version::VERSION_PATTERN})\n/
    return unless contents =~ regexp
    $1
  end
  private_class_method :lockfile_version

  def self.lockfile_contents
    gemfile = gemfile_path

    return unless gemfile

    lockfile = ENV["BUNDLE_LOCKFILE"]
    lockfile = nil if lockfile&.empty?

    lockfile ||= case gemfile
                 when "gems.rb" then "gems.locked"
                 else "#{gemfile}.lock"
    end

    return unless File.file?(lockfile)

    File.read(lockfile)
  end
  private_class_method :lockfile_contents

  # BUNDLE_VERSION is read before the config files here, unlike everywhere
  # else in Bundler, so the env var alone is enough to pick the version that
  # runs without editing a config file first.
  def self.bundle_config_version
    Gem::BundlerSettings.env("version") || Gem::BundlerSettings.from_config_files("version")
  end
  private_class_method :bundle_config_version

  def self.gemfile_path
    Gem::BundlerSettings.gemfile_path
  end
  private_class_method :gemfile_path
end
