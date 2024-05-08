# frozen_string_literal: true

require_relative "gem_parser"

module Bundler
  class CompactIndexClient
    class Cache
      attr_reader :directory

      def initialize(directory)
        @directory = Pathname.new(directory).expand_path
        info_roots.each {|dir| mkdir(dir) }
        mkdir(info_etag_root)
      end

      def names
        lines(names_path)
      end

      def names_path
        directory.join("names")
      end

      def names_etag_path
        directory.join("names.etag")
      end

      def versions
        versions_by_name = Hash.new {|hash, key| hash[key] = [] }
        info_checksums_by_name = {}

        lines(versions_path).each do |line|
          name, versions_string, info_checksum = line.split(" ", 3)
          info_checksums_by_name[name] = info_checksum || ""
          versions_string.split(",") do |version|
            delete = version.delete_prefix!("-")
            version = version.split("-", 2).unshift(name)
            if delete
              versions_by_name[name].delete(version)
            else
              versions_by_name[name] << version
            end
          end
        end

        [versions_by_name, info_checksums_by_name]
      end

      def versions_path
        directory.join("versions")
      end

      def versions_etag_path
        directory.join("versions.etag")
      end

      def checksums
        lines(versions_path).each_with_object({}) do |line, checksums|
          parse_version_checksum(line, checksums)
        end
      end

      def dependencies(name)
        lines(info_path(name)).map do |line|
          parse_gem(line)
        end
      end

      def info_path(name)
        name = name.to_s
        if /[^a-z0-9_-]/.match?(name)
          name += "-#{SharedHelpers.digest(:MD5).hexdigest(name).downcase}"
          info_roots.last.join(name)
        else
          info_roots.first.join(name)
        end
      end

      def info_etag_path(name)
        name = name.to_s
        info_etag_root.join("#{name}-#{SharedHelpers.digest(:MD5).hexdigest(name).downcase}")
      end

      private

      def mkdir(dir)
        SharedHelpers.filesystem_access(dir) do
          FileUtils.mkdir_p(dir)
        end
      end

      def lines(path)
        return [] unless path.file?
        lines = SharedHelpers.filesystem_access(path, :read, &:read).split("\n")
        header = lines.index("---")
        header ? lines[header + 1..-1] : lines
      end

      def parse_gem(line)
        @dependency_parser ||= GemParser.new
        @dependency_parser.parse(line)
      end

      # This is mostly the same as `split(" ", 3)` but it avoids allocating extra objects.
      # This method gets called at least once for every gem when parsing versions.
      def parse_version_checksum(line, checksums)
        line.freeze # allows slicing into the string to not allocate a copy of the line
        name_end = line.index(" ")
        checksum_start = line.index(" ", name_end + 1) + 1
        checksum_end = line.size - checksum_start
        # freeze name since it is used as a hash key
        # pre-freezing means a frozen copy isn't created
        name = line[0, name_end].freeze
        checksum = line[checksum_start, checksum_end]
        checksums[name] = checksum
      end

      def info_roots
        [
          directory.join("info"),
          directory.join("info-special-characters"),
        ]
      end

      def info_etag_root
        directory.join("info-etags")
      end
    end
  end
end
