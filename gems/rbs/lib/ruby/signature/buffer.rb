module Ruby
  module Signature
    class Buffer
      attr_reader :name
      attr_reader :content
      attr_reader :lines
      attr_reader :ranges

      def initialize(name:, content:)
        @name = name
        @content = content

        @lines = content.lines

        @ranges = []
        offset = 0
        lines.each do |line|
          size = line.size
          range = offset...(offset+size)
          ranges << range
          offset += size
        end
      end

      def pos_to_loc(pos)
        index = ranges.bsearch_index do |range|
          pos < range.end
        end

        if index
          [index + 1, pos - ranges[index].begin]
        else
          [ranges.size + 1, 0]
        end
      end

      def loc_to_pos(loc)
        line, column = loc

        if range = ranges[line - 1]
          range.begin + column
        else
          last_position
        end
      end

      def last_position
        content.size
      end
    end
  end
end
