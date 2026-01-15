# frozen_string_literal: true

module Bundler
  # Represents metadata from when the Bundler gem was built.
  module BuildMetadata
    # begin ivars
    @built_at = nil
    # end ivars

    # A hash representation of the build metadata.
    def self.to_h
      {
        "Timestamp" => timestamp,
        "Git SHA" => git_commit_sha,
      }
    end

    # A timestamp representing the date the bundler gem was built, or the
    # current time if never built
    def self.timestamp
      @timestamp ||= @built_at || Time.now.utc.strftime("%Y-%m-%d").freeze
    end

    # A string representing the date the bundler gem was built.
    def self.built_at
      @built_at
    end

    # The SHA for the git commit the bundler gem was built from.
    def self.git_commit_sha
      return @git_commit_sha if instance_variable_defined? :@git_commit_sha

      # If Bundler has been installed without its .git directory and without a
      # commit instance variable then we can't determine its commits SHA.
      git_dir = File.expand_path("../../../.git", __dir__)
      if File.directory?(git_dir)
        return @git_commit_sha = IO.popen(%w[git rev-parse --short HEAD], { chdir: git_dir }, &:read).strip.freeze
      end

      @git_commit_sha ||= "unknown"
    end
  end
end
