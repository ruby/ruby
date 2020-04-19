module Ruby
  module Signature
    class Location
      attr_reader :buffer
      attr_reader :start_pos
      attr_reader :end_pos

      def initialize(buffer:, start_pos:, end_pos:)
        @buffer = buffer
        @start_pos = start_pos
        @end_pos = end_pos
      end

      def inspect
        "#<#{self.class}:#{self.__id__} @buffer=#{buffer.name}, @pos=#{start_pos}...#{end_pos}, source='#{source.lines.first}', start_line=#{start_line}, start_column=#{start_column}>"
      end

      def name
        buffer.name
      end

      def start_line
        start_loc[0]
      end

      def start_column
        start_loc[1]
      end

      def end_line
        end_loc[0]
      end

      def end_column
        end_loc[1]
      end

      def start_loc
        @start_loc ||= buffer.pos_to_loc(start_pos)
      end

      def end_loc
        @end_loc ||= buffer.pos_to_loc(end_pos)
      end

      def source
        @source ||= buffer.content[start_pos...end_pos]
      end

      def to_s
        "#{name || "-"}:#{start_line}:#{start_column}...#{end_line}:#{end_column}"
      end

      def self.to_string(location, default: "*:*:*...*:*")
        location&.to_s || default
      end

      def ==(other)
        other.is_a?(Location) &&
          other.buffer == buffer &&
          other.start_pos == start_pos &&
          other.end_pos == end_pos
      end

      def +(other)
        if other
          raise "Invalid concat: buffer=#{buffer.name}, other.buffer=#{other.buffer.name}" unless other.buffer == buffer

          self.class.new(buffer: buffer,
                         start_pos: start_pos,
                         end_pos: other.end_pos)
        else
          self
        end
      end

      def self.concat(*locations)
        locations.inject {|l1, l2| l1 + l2 }
      end

      def pred?(loc)
        loc.is_a?(Location) &&
          loc.name == name &&
          loc.start_pos == end_pos
      end

      def to_json(*args)
        {
          start: {
            line: start_line,
            column: start_column
          },
          end: {
            line: end_line,
            column: end_column
          },
          buffer: {
            name: name&.to_s
          }
        }.to_json(*args)
      end
    end
  end
end
