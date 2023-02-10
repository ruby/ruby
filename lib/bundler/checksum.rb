# frozen_string_literal: true

module Bundler
  class Checksum
    attr_reader :name, :version, :platform, :checksums

    SHA256 = %r{\Asha256-([a-z0-9]{64}|[A-Za-z0-9+\/=]{44})\z}.freeze

    def initialize(name, version, platform, checksums = [])
      @name     = name
      @version  = version
      @platform = platform || Gem::Platform::RUBY
      @checksums = checksums

      # can expand this validation when we support more hashing algos later
      if @checksums.any? && @checksums.all? {|c| c !~ SHA256 }
        raise ArgumentError, "invalid checksums (#{@checksums})"
      end
    end

    def self.digest_from_file_source(file_source)
      raise ArgumentError, "not a valid file source: #{file_source}" unless file_source.respond_to?(:with_read_io)

      file_source.with_read_io do |io|
        digest = Bundler::SharedHelpers.digest(:SHA256).new
        digest << io.read(16_384) until io.eof?
        io.rewind
        digest
      end
    end

    def full_name
      GemHelpers.spec_full_name(@name, @version, @platform)
    end

    def match_spec?(spec)
      name == spec.name &&
        version == spec.version &&
        platform.to_s == spec.platform.to_s
    end

    def to_lock
      out = String.new
      out << "  #{GemHelpers.lock_name(name, version, platform)}"
      out << " #{sha256}" if sha256
      out << "\n"

      out
    end

    private

    def sha256
      @checksums.find {|c| c =~ SHA256 }
    end
  end
end
