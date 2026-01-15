# frozen_string_literal: true

require_relative "path"
require_relative "helpers"

module Spec
  module BuildMetadata
    include Spec::Path
    include Spec::Helpers

    def write_build_metadata(dir: source_root, version: Bundler::VERSION)
      build_metadata = {
        git_commit_sha: git_commit_sha,
        built_at: release_date_for(version, dir: dir),
      }

      replace_build_metadata(build_metadata, dir: dir)
    end

    def reset_build_metadata(dir: source_root)
      build_metadata = {
        built_at: nil,
      }

      replace_build_metadata(build_metadata, dir: dir)
    end

    private

    def replace_build_metadata(build_metadata, dir:)
      build_metadata_file = File.expand_path("lib/bundler/build_metadata.rb", dir)

      ivars = build_metadata.sort.map do |k, v|
        "    @#{k} = #{loaded_gemspec.send(:ruby_code, v)}"
      end.join("\n")

      contents = File.read(build_metadata_file)
      contents.sub!(/^(\s+# begin ivars).+(^\s+# end ivars)/m, "\\1\n#{ivars}\n\\2")
      File.open(build_metadata_file, "w") {|f| f << contents }
    end

    def git_commit_sha
      ruby_core_tarball? ? "unknown" : git("rev-parse --short HEAD", source_root).strip
    end

    def release_date_for(version, dir:)
      changelog = File.expand_path("CHANGELOG.md", dir)
      File.readlines(changelog)[2].scan(/^## #{Regexp.escape(version)} \((.*)\)/).first&.first if File.exist?(changelog)
    end

    extend self
  end
end
