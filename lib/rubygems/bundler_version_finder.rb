# frozen_string_literal: true

module Gem::BundlerVersionFinder
  def self.bundler_version
    return if bundle_config_version == "system"

    v = ENV["BUNDLER_VERSION"]
    v = nil if v&.empty?

    v ||= bundle_update_bundler_version
    return if v == true

    v ||= lockfile_version
    return unless v

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
    gemfile = ENV["BUNDLE_GEMFILE"]
    gemfile = nil if gemfile&.empty?

    unless gemfile
      begin
        Gem::Util.traverse_parents(Dir.pwd) do |directory|
          next unless gemfile = Gem::GEM_DEP_FILES.find {|f| File.file?(f) }

          gemfile = File.join directory, gemfile
          break
        end
      rescue Errno::ENOENT
        return
      end
    end

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

  def self.bundle_config_version
    config_file = bundler_config_file
    return unless config_file && File.file?(config_file)

    contents = File.read(config_file)
    contents =~ /^BUNDLE_VERSION:\s*["']?([^"'\s]+)["']?\s*$/

    $1
  end
  private_class_method :bundle_config_version

  def self.bundler_config_file
    # see Bundler::Settings#global_config_file and local_config_file
    # global
    if ENV["BUNDLE_CONFIG"] && !ENV["BUNDLE_CONFIG"].empty?
      ENV["BUNDLE_CONFIG"]
    elsif ENV["BUNDLE_USER_CONFIG"] && !ENV["BUNDLE_USER_CONFIG"].empty?
      ENV["BUNDLE_USER_CONFIG"]
    elsif ENV["BUNDLE_USER_HOME"] && !ENV["BUNDLE_USER_HOME"].empty?
      ENV["BUNDLE_USER_HOME"] + "config"
    elsif Gem.user_home && !Gem.user_home.empty?
      Gem.user_home + ".bundle/config"
    else
      # local
      "config"
    end
  end
  private_class_method :bundler_config_file
end
