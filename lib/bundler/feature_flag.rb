# frozen_string_literal: true

module Bundler
  class FeatureFlag
    (1..10).each {|v| define_method("bundler_#{v}_mode?") { @major_version >= v } }

    def removed_major?(target_major_version)
      @major_version > target_major_version
    end

    def deprecated_major?(target_major_version)
      @major_version >= target_major_version
    end

    def initialize(bundler_version)
      @bundler_version = Gem::Version.create(bundler_version)
      @major_version = @bundler_version.segments.first
    end
  end
end
