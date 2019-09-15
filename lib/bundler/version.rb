# frozen_string_literal: false

module Bundler
  VERSION = "2.1.0.pre.2".freeze

  def self.bundler_major_version
    @bundler_major_version ||= VERSION.split(".").first.to_i
  end
end
