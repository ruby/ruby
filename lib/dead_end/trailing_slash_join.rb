# frozen_string_literal: true

module DeadEnd
  # Handles code that contains trailing slashes
  # by turning multiple lines with trailing slash(es) into
  # a single code line
  #
  #   expect(code_lines.join).to eq(<<~EOM)
  #     it "trailing \
  #        "slash" do
  #     end
  #   EOM
  #
  #   lines = TrailngSlashJoin(code_lines: code_lines).call
  #   expect(lines.first.to_s).to eq(<<~EOM)
  #     it "trailing \
  #        "slash" do
  #   EOM
  #
  class TrailingSlashJoin
    def initialize(code_lines:)
      @code_lines = code_lines
      @code_lines_dup = code_lines.dup
    end

    def call
      @trailing_lines = []
      @code_lines.select(&:trailing_slash?).each do |trailing|
        stop_next = false
        lines = @code_lines[trailing.index..-1].take_while do |line|
          next false if stop_next

          if !line.trailing_slash?
            stop_next = true
          end

          true
        end

        joined_line = CodeLine.new(line: lines.map(&:original_line).join, index: trailing.index)

        @code_lines_dup[trailing.index] = joined_line

        @trailing_lines << joined_line

        lines.shift # Don't hide first trailing slash line
        lines.each(&:mark_invisible)
      end

      return @code_lines_dup
    end
  end
end
