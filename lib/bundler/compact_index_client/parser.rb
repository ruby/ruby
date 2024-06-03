# frozen_string_literal: true

module Bundler
  class CompactIndexClient
    class Parser
      # `compact_index` - an object responding to #names, #versions, #info(name, checksum),
      #                   returning the file contents as a string
      def initialize(compact_index)
        @compact_index = compact_index
        @info_checksums = nil
        @versions_by_name = nil
        @available = nil
        @gem_parser = nil
        @versions_data = nil
      end

      def names
        lines(@compact_index.names)
      end

      def versions
        @versions_by_name ||= Hash.new {|hash, key| hash[key] = [] }
        @info_checksums = {}

        lines(@compact_index.versions).each do |line|
          name, versions_string, checksum = line.split(" ", 3)
          @info_checksums[name] = checksum || ""
          versions_string.split(",") do |version|
            delete = version.delete_prefix!("-")
            version = version.split("-", 2).unshift(name)
            if delete
              @versions_by_name[name].delete(version)
            else
              @versions_by_name[name] << version
            end
          end
        end

        @versions_by_name
      end

      def info(name)
        data = @compact_index.info(name, info_checksum(name))
        lines(data).map {|line| gem_parser.parse(line).unshift(name) }
      end

      # parse the last, most recently updated line of the versions file to determine availability
      def available?
        return @available unless @available.nil?
        return @available = false unless versions_data&.size&.nonzero?

        line_end = versions_data.size - 1
        return @available = false if versions_data[line_end] != "\n"

        line_start = versions_data.rindex("\n", line_end - 1)
        line_start ||= -1 # allow a single line versions file

        @available = !split_last_word(versions_data, line_start + 1, line_end).nil?
      end

      private

      # Search for a line starting with gem name, then return last space-separated word (the checksum)
      def info_checksum(name)
        return unless versions_data
        return unless (line_start = rindex_of_gem(name))
        return unless (line_end = versions_data.index("\n", line_start))
        split_last_word(versions_data, line_start, line_end)
      end

      def gem_parser
        @gem_parser ||= GemParser.new
      end

      def versions_data
        @versions_data ||= begin
          data = @compact_index.versions
          strip_header!(data) if data
          data.freeze
        end
      end

      def rindex_of_gem(name)
        if (pos = versions_data.rindex("\n#{name} "))
          pos + 1
        elsif versions_data.start_with?("#{name} ")
          0
        end
      end

      # This is similar to `string.split(" ").last` but it avoids allocating extra objects.
      def split_last_word(string, line_start, line_end)
        return unless line_start < line_end && line_start >= 0
        word_start = string.rindex(" ", line_end).to_i + 1
        return if word_start < line_start
        string[word_start, line_end - word_start]
      end

      def lines(string)
        return [] if string.nil? || string.empty?
        strip_header!(string)
        string.split("\n")
      end

      def strip_header!(string)
        header_end = string.index("---\n")
        string.slice!(0, header_end + 4) if header_end
      end
    end
  end
end
