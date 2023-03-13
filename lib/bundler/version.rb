# frozen_string_literal: false

module Bundler
  VERSION = (ENV["BUNDLER_3_MODE"] == "true" ? "3.0.0" : "2.7.0.dev").freeze

  def self.bundler_major_version
    @bundler_major_version ||= VERSION.split(".").first.to_i
  end

  def self.gem_version
    @gem_version ||= Gem::Version.create(VERSION)
  end
end
