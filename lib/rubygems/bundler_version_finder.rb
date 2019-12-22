# frozen_string_literal: true

require "rubygems/util"

module Gem::BundlerVersionFinder
  def self.bundler_version
    version, _ = bundler_version_with_reason

    return unless version

    Gem::Version.new(version)
  end

  def self.bundler_version_with_reason
    if v = ENV["BUNDLER_VERSION"]
      return [v, "`$BUNDLER_VERSION`"]
    end
    if v = bundle_update_bundler_version
      return if v == true
      return [v, "`bundle update --bundler`"]
    end
    v, lockfile = lockfile_version
    if v
      return [v, "your #{lockfile}"]
    end
  end

  def self.missing_version_message
    return unless vr = bundler_version_with_reason
    <<-EOS
Could not find 'bundler' (#{vr.first}) required by #{vr.last}.
To update to the latest version installed on your system, run `bundle update --bundler`.
To install the missing version, run `gem install bundler:#{vr.first}`
    EOS
  end

  def self.compatible?(spec)
    return true unless spec.name == "bundler".freeze
    return true unless bundler_version = self.bundler_version

    spec.version.segments.first == bundler_version.segments.first
  end

  def self.filter!(specs)
    return unless bundler_version = self.bundler_version

    specs.reject! { |spec| spec.version.segments.first != bundler_version.segments.first }

    exact_match_index = specs.find_index { |spec| spec.version == bundler_version }
    return unless exact_match_index

    specs.unshift(specs.delete_at(exact_match_index))
  end

  def self.bundle_update_bundler_version
    return unless File.basename($0) == "bundle".freeze
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
    return unless lockfile = lockfile_contents
    lockfile, contents = lockfile
    lockfile ||= "lockfile"
    regexp = /\n\nBUNDLED WITH\n\s{2,}(#{Gem::Version::VERSION_PATTERN})\n/
    return unless contents =~ regexp
    [$1, lockfile]
  end
  private_class_method :lockfile_version

  def self.lockfile_contents
    gemfile = ENV["BUNDLE_GEMFILE"]
    gemfile = nil if gemfile && gemfile.empty?
    Gem::Util.traverse_parents Dir.pwd do |directory|
      next unless gemfile = Gem::GEM_DEP_FILES.find { |f| File.file?(f.tap(&Gem::UNTAINT)) }

      gemfile = File.join directory, gemfile
      break
    end unless gemfile

    return unless gemfile

    lockfile = case gemfile
               when "gems.rb" then "gems.locked"
               else "#{gemfile}.lock"
               end.dup.tap(&Gem::UNTAINT)

    return unless File.file?(lockfile)

    [lockfile, File.read(lockfile)]
  end
  private_class_method :lockfile_contents
end
