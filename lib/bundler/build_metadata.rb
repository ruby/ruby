# frozen_string_literal: true

module Bundler
  # Represents metadata from when the Bundler gem was built.
  module BuildMetadata
    # begin ivars
    @release = false
    # end ivars

    # A hash representation of the build metadata.
    def self.to_h
      {
        "Built At" => built_at,
        "Git SHA" => git_commit_sha,
        "Released Version" => release?,
      }
    end

    # A string representing the date the bundler gem was built.
    def self.built_at
      @built_at ||= Time.now.utc.strftime("%Y-%m-%d").freeze
    end

    # The SHA for the git commit the bundler gem was built from.
    def self.git_commit_sha
      @git_commit_sha ||= Dir.chdir(File.expand_path("..", __FILE__)) do
        `git rev-parse --short HEAD`.strip.freeze
      end
    end

    # Whether this is an official release build of Bundler.
    def self.release?
      @release
    end
  end
end
