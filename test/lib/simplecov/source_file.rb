module SimpleCov
  #
  # Representation of a source file including it's coverage data, source code,
  # source lines and featuring helpers to interpret that data.
  #
  class SourceFile
    # Representation of a single line in a source file including
    # this specific line's source code, line_number and code coverage,
    # with the coverage being either nil (coverage not applicable, e.g. comment
    # line), 0 (line not covered) or >1 (the amount of times the line was
    # executed)
    class Line
      # The source code for this line. Aliased as :source
      attr_reader :src
      # The line number in the source file. Aliased as :line, :number
      attr_reader :line_number
      # The coverage data for this line: either nil (never), 0 (missed) or >=1 (times covered)
      attr_reader :coverage
      # Whether this line was skipped
      attr_reader :skipped

      # Lets grab some fancy aliases, shall we?
      alias_method :source, :src
      alias_method :line, :line_number
      alias_method :number, :line_number

      def initialize(src, line_number, coverage)
        raise ArgumentError, "Only String accepted for source" unless src.kind_of?(String)
        raise ArgumentError, "Only Fixnum accepted for line_number" unless line_number.kind_of?(Fixnum)
        raise ArgumentError, "Only Fixnum and nil accepted for coverage" unless coverage.kind_of?(Fixnum) or coverage.nil?
        @src, @line_number, @coverage = src, line_number, coverage
        @skipped = false
      end

      # Returns true if this is a line that should have been covered, but was not
      def missed?
        not never? and not skipped? and coverage == 0
      end

      # Returns true if this is a line that has been covered
      def covered?
        not never? and not skipped? and coverage > 0
      end

      # Returns true if this line is not relevant for coverage
      def never?
        not skipped? and coverage.nil?
      end

      # Flags this line as skipped
      def skipped!
        @skipped = true
      end

      # Returns true if this line was skipped, false otherwise. Lines are skipped if they are wrapped with
      # # :nocov: comment lines.
      def skipped?
	      !!skipped
      end

      # The status of this line - either covered, missed, skipped or never. Useful i.e. for direct use
      # as a css class in report generation
      def status
        return 'skipped' if skipped?
        return 'never' if never?
        return 'missed' if missed?
        return 'covered' if covered?
      end
    end

    # The full path to this source file (e.g. /User/colszowka/projects/simplecov/lib/simplecov/source_file.rb)
    attr_reader :filename
    # The array of coverage data received from the Coverage.result
    attr_reader :coverage
    # The source code for this file. Aliased as :source
    attr_reader :src
    alias_method :source, :src

    def initialize(filename, coverage)
      @filename, @coverage = filename, coverage
      File.open(filename, "rb") {|f| @src = f.readlines }
    end

    # Returns all source lines for this file as instances of SimpleCov::SourceFile::Line,
    # and thus including coverage data. Aliased as :source_lines
    def lines
      return @lines if defined? @lines

      # Warning to identify condition from Issue #56
      if coverage.size > src.size
        $stderr.puts "Warning: coverage data provided by Coverage [#{coverage.size}] exceeds number of lines in #{filename} [#{src.size}]"
      end

      # Initialize lines
      @lines = []
      src.each_with_index do |src, i|
        @lines << SimpleCov::SourceFile::Line.new(src, i+1, coverage[i])
      end
      process_skipped_lines!
      @lines
    end
    alias_method :source_lines, :lines

    # Access SimpleCov::SourceFile::Line source lines by line number
    def line(number)
      lines[number-1]
    end

    # The coverage for this file in percent. 0 if the file has no relevant lines
    def covered_percent
      return 100.0 if lines.length == 0 or lines.length == never_lines.count
      relevant_lines = lines.count - never_lines.count - skipped_lines.count
      if relevant_lines == 0
        0.0
      else
        Float((covered_lines.count) * 100.0 / relevant_lines.to_f)
      end
    end

    def covered_strength
      return 0.0 if lines.length == 0 or lines.length == never_lines.count

      lines_strength = 0
      lines.each do |c|
        lines_strength += c.coverage if c.coverage
      end

      effective_lines_count = Float(lines.count - never_lines.count - skipped_lines.count)

      if effective_lines_count == 0
        0.0
      else
        strength = lines_strength / effective_lines_count
        round_float(strength, 1)
      end
    end

    # Returns all covered lines as SimpleCov::SourceFile::Line
    def covered_lines
      @covered_lines ||= lines.select {|c| c.covered? }
    end

    # Returns all lines that should have been, but were not covered
    # as instances of SimpleCov::SourceFile::Line
    def missed_lines
      @missed_lines ||= lines.select {|c| c.missed? }
    end

    # Returns all lines that are not relevant for coverage as
    # SimpleCov::SourceFile::Line instances
    def never_lines
      @never_lines ||= lines.select {|c| c.never? }
    end

    # Returns all lines that were skipped as SimpleCov::SourceFile::Line instances
    def skipped_lines
      @skipped_lines ||= lines.select {|c| c.skipped? }
    end

    # Returns the number of relevant lines (covered + missed)
    def lines_of_code
      covered_lines.count + missed_lines.count
    end

    # Will go through all source files and mark lines that are wrapped within # :nocov: comment blocks
    # as skipped.
    def process_skipped_lines!
      skipping = false
      lines.each do |line|
        if line.src =~ /^([\s]*)#([\s]*)(\:#{SimpleCov.nocov_token}\:)/
          skipping = !skipping
        else
          line.skipped! if skipping
        end
      end
    end

    private

    # ruby 1.9 could use Float#round(places) instead
    # @return [Float]
    def round_float(float, places)
      factor = Float(10 * places)
      Float((float * factor).round / factor)
    end
  end
end

