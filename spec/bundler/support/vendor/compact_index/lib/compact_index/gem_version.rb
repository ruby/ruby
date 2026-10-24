# frozen_string_literal: true

module VendoredCompactIndex
  module GemVersionMethods
    def version_token
      return "#{number}-#{content_address}" if content_address?

      if platform.nil? || platform == "ruby"
        number
      else
        "#{number}-#{platform}"
      end
    end

    def <=>(other)
      number_comp = number <=> other.number

      if number_comp.zero?
        [platform, ruby_abi, content_address].compact <=>
          [other.platform, other.ruby_abi, other.content_address].compact
      else
        number_comp
      end
    end

    def to_line
      line = "#{version_token} #{deps_line}|checksum:#{checksum}"
      line << ",ruby:#{ruby_version_line}" if ruby_version && ruby_version != ">= 0"
      line << ",rubygems:#{rubygems_version_line}" if rubygems_version && rubygems_version != ">= 0"
      line << ",platform:#{platform}" if content_address?
      line
    end

    private

    def content_address?
      !content_address.nil? && !content_address.empty?
    end

    def ruby_version_line
      join_multiple(ruby_version)
    end

    def rubygems_version_line
      join_multiple(rubygems_version)
    end

    def deps_line
      return "" if dependencies.nil?

      dependencies.map do |d|
        [d[:gem], join_multiple(d.version_and_platform)].join(":")
      end.join(",")
    end

    def join_multiple(requirements)
      requirements = requirements.split(", ")
      requirements.sort!
      requirements.join("&")
    end
  end

  GemVersionV2 = Struct.new(:number, :platform, :checksum, :info_checksum,
                            :dependencies, :ruby_version, :rubygems_version,
                            :created_at, :ruby_abi, :content_address) do
    include GemVersionMethods

    def to_line
      line = super
      line << ",created_at:#{created_at}" if created_at
      line
    end
  end
end
