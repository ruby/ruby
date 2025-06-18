# frozen_string_literal: false

module Bundler
  VERSION = "2.7.0.dev".freeze

  def self.bundler_major_version
    @bundler_major_version ||= gem_version.segments.first
  end

  def self.gem_version
    @gem_version ||= Gem::Version.create(VERSION)
  end
end
