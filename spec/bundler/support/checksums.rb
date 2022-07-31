# frozen_string_literal: true

module Spec
  module Checksums
    class ChecksumsBuilder
      def initialize
        @checksums = []
      end

      def repo_gem(gem_repo, gem_name, gem_version, platform = nil)
        gem_file = if platform
          "#{gem_repo}/gems/#{gem_name}-#{gem_version}-#{platform}.gem"
        else
          "#{gem_repo}/gems/#{gem_name}-#{gem_version}.gem"
        end

        checksum = sha256_checksum(gem_file)
        @checksums << Bundler::Checksum.new(gem_name, gem_version, platform, checksum)
      end

      def to_lock
        @checksums.map(&:to_lock).join.strip
      end

      private

      def sha256_checksum(file)
        File.open(file) do |f|
          digest = Bundler::SharedHelpers.digest(:SHA256).new
          digest << f.read(16_384) until f.eof?

          "sha256-#{digest.hexdigest!}"
        end
      end
    end

    def construct_checksum_section
      checksums = ChecksumsBuilder.new

      yield checksums

      checksums.to_lock
    end

    def checksum_for_repo_gem(gem_repo, gem_name, gem_version, platform = nil)
      construct_checksum_section do |c|
        c.repo_gem(gem_repo, gem_name, gem_version, platform)
      end
    end
  end
end
