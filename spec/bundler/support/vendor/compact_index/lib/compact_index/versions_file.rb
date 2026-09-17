# frozen_string_literal: true

require "time"
require "date"
require "digest"

module VendoredCompactIndex
  class VersionsFile
    def initialize(file = nil)
      @path = file || "/versions.list"
    end

    def contents(gems = nil, args = {})
      gems = calculate_info_checksums(gems) if args.delete(:calculate_info_checksums) { false }

      raise ArgumentError, "Unknown options: #{args.keys.join(', ')}" unless args.empty?

      File.read(@path).tap do |out|
        out << gem_lines(gems) if gems
      end
    end

    def updated_at
      created_at_header(@path) || Time.at(0).utc.to_datetime
    end

    def create(gems, timestamp = Time.now.iso8601)
      gems.sort!
      create_from_sorted(gems, timestamp)
    end

    def create_from_sorted(gems, timestamp = Time.now.iso8601)
      File.open(@path, "w") do |io|
        io.write "created_at: #{timestamp}\n---\n"
        write_gem_lines(io, gems)
      end
    end

    private

    def gem_lines(gems)
      lines = +""
      write_gem_lines(lines, gems)
      lines
    end

    def write_gem_lines(io, gems)
      gems.each do |gem|
        version_numbers = gem.versions.map(&:version_token).join(",")
        io << gem.name <<
          " " << version_numbers <<
          " #{gem.versions.last.info_checksum}\n"
      end
    end

    def calculate_info_checksums(gems)
      gems.each do |gem|
        info_checksum = Digest::MD5.hexdigest(VendoredCompactIndex.info(gem[:versions]))
        gem[:versions].last[:info_checksum] = info_checksum
      end
    end

    def created_at_header(path)
      return unless File.exist? path

      File.open(path) do |file|
        file.each_line do |line|
          line.match(/created_at: (.*)\n|---\n/) do |match|
            return match[1] && DateTime.parse(match[1])
          end
        end
      end

      nil
    end
  end
end
