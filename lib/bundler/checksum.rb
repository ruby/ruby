# frozen_string_literal: true

module Bundler
  class Checksum
    attr_reader :name, :version, :platform
    attr_accessor :checksum

    SHA256 = /\Asha256-([a-z0-9]{64}|[A-Za-z0-9+\/=]{44})\z/.freeze

    def initialize(name, version, platform, checksum = nil)
      @name     = name
      @version  = version
      @platform = platform || Gem::Platform::RUBY
      @checksum = checksum

      if @checksum && @checksum !~ SHA256
        raise ArgumentError, "invalid checksum (#{@checksum})"
      end
    end

    def match_spec?(spec)
      name == spec.name &&
        version == spec.version &&
        platform.to_s == spec.platform.to_s
    end

    def to_lock
      out = String.new

      if platform == Gem::Platform::RUBY
        out << "  #{name} (#{version})"
      else
        out << "  #{name} (#{version}-#{platform})"
      end

      out << " #{checksum}" if checksum
      out << "\n"

      out
    end
  end
end
