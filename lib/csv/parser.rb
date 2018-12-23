# frozen_string_literal: true

require "strscan"

require_relative "match_p"
require_relative "row"
require_relative "table"

using CSV::MatchP if CSV.const_defined?(:MatchP)

class CSV
  class Parser
    class InvalidEncoding < StandardError
    end

    class Scanner < StringScanner
      alias_method :scan_all, :scan

      def initialize(*args)
        super
        @keeps = []
      end

      def keep_start
        @keeps.push(pos)
      end

      def keep_end
        start = @keeps.pop
        string[start, pos - start]
      end

      def keep_back
        self.pos = @keeps.pop
      end

      def keep_drop
        @keeps.pop
      end
    end

    class InputsScanner
      def initialize(inputs, encoding, chunk_size: 8192)
        @inputs = inputs.dup
        @encoding = encoding
        @chunk_size = chunk_size
        @last_scanner = @inputs.empty?
        @keeps = []
        read_chunk
      end

      def scan(pattern)
        value = @scanner.scan(pattern)
        return value if @last_scanner

        if value
          read_chunk if @scanner.eos?
          return value
        else
          nil
        end
      end

      def scan_all(pattern)
        value = @scanner.scan(pattern)
        return value if @last_scanner

        return nil if value.nil?
        while @scanner.eos? and read_chunk and (sub_value = @scanner.scan(pattern))
          value << sub_value
        end
        value
      end

      def eos?
        @scanner.eos?
      end

      def keep_start
        @keeps.push([@scanner.pos, nil])
      end

      def keep_end
        start, buffer = @keeps.pop
        keep = @scanner.string[start, @scanner.pos - start]
        if buffer
          buffer << keep
          keep = buffer
        end
        keep
      end

      def keep_back
        start, buffer = @keeps.pop
        if buffer
          string = @scanner.string
          keep = string[start, string.size - start]
          if keep and not keep.empty?
            @inputs.unshift(StringIO.new(keep))
            @last_scanner = false
          end
          @scanner = StringScanner.new(buffer)
        else
          @scanner.pos = start
        end
      end

      def keep_drop
        @keeps.pop
      end

      def rest
        @scanner.rest
      end

      private
      def read_chunk
        return false if @last_scanner

        unless @keeps.empty?
          keep = @keeps.last
          keep_start = keep[0]
          string = @scanner.string
          keep_data = string[keep_start, @scanner.pos - keep_start]
          if keep_data
            keep_buffer = keep[1]
            if keep_buffer
              keep_buffer << keep_data
            else
              keep[1] = keep_data.dup
            end
          end
          keep[0] = 0
        end

        input = @inputs.first
        case input
        when StringIO
          string = input.string
          raise InvalidEncoding unless string.valid_encoding?
          @scanner = StringScanner.new(string)
          @inputs.shift
          @last_scanner = @inputs.empty?
          true
        else
          chunk = input.gets(nil, @chunk_size)
          if chunk
            raise InvalidEncoding unless chunk.valid_encoding?
            @scanner = StringScanner.new(chunk)
            if input.respond_to?(:eof?) and input.eof?
              @inputs.shift
              @last_scanner = @inputs.empty?
            end
            true
          else
            @scanner = StringScanner.new("".encode(@encoding))
            @inputs.shift
            @last_scanner = @inputs.empty?
            if @last_scanner
              false
            else
              read_chunk
            end
          end
        end
      end
    end

    def initialize(input, options)
      @input = input
      @options = options
      @samples = []

      prepare
    end

    def column_separator
      @column_separator
    end

    def row_separator
      @row_separator
    end

    def quote_character
      @quote_character
    end

    def field_size_limit
      @field_size_limit
    end

    def skip_lines
      @skip_lines
    end

    def unconverted_fields?
      @unconverted_fields
    end

    def headers
      @headers
    end

    def header_row?
      @use_headers and @headers.nil?
    end

    def return_headers?
      @return_headers
    end

    def skip_blanks?
      @skip_blanks
    end

    def liberal_parsing?
      @liberal_parsing
    end

    def lineno
      @lineno
    end

    def line
      last_line
    end

    def parse(&block)
      return to_enum(__method__) unless block_given?

      if @return_headers and @headers
        headers = Row.new(@headers, @raw_headers, true)
        if @unconverted_fields
          headers = add_unconverted_fields(headers, [])
        end
        yield headers
      end

      row = []
      begin
        @scanner = build_scanner
        skip_needless_lines
        start_row
        while true
          @quoted_column_value = false
          @unquoted_column_value = false
          value = parse_column_value
          if value and @field_size_limit and value.size >= @field_size_limit
            raise MalformedCSVError.new("Field size exceeded", @lineno + 1)
          end
          if parse_column_end
            row << value
          elsif parse_row_end
            if row.empty? and value.nil?
              emit_row([], &block) unless @skip_blanks
            else
              row << value
              emit_row(row, &block)
              row = []
            end
            skip_needless_lines
            start_row
          elsif @scanner.eos?
            return if row.empty? and value.nil?
            row << value
            emit_row(row, &block)
            return
          else
            if @quoted_column_value
              message = "Do not allow except col_sep_split_separator " +
                "after quoted fields"
              raise MalformedCSVError.new(message, @lineno + 1)
            elsif @unquoted_column_value and @scanner.scan(@cr_or_lf)
              message = "Unquoted fields do not allow \\r or \\n"
              raise MalformedCSVError.new(message, @lineno + 1)
            elsif @scanner.rest.start_with?(@quote_character)
              message = "Illegal quoting"
              raise MalformedCSVError.new(message, @lineno + 1)
            else
              raise MalformedCSVError.new("TODO: Meaningful message",
                                          @lineno + 1)
            end
          end
        end
      rescue InvalidEncoding
        message = "Invalid byte sequence in #{@encoding}"
        raise MalformedCSVError.new(message, @lineno + 1)
      end
    end

    private
    def prepare
      prepare_variable
      prepare_regexp
      prepare_line
      prepare_header
      prepare_parser
    end

    def prepare_variable
      @encoding = @options[:encoding]
      @liberal_parsing = @options[:liberal_parsing]
      @unconverted_fields = @options[:unconverted_fields]
      @field_size_limit = @options[:field_size_limit]
      @skip_blanks = @options[:skip_blanks]
      @fields_converter = @options[:fields_converter]
      @header_fields_converter = @options[:header_fields_converter]
    end

    def prepare_regexp
      @column_separator = @options[:column_separator].to_s.encode(@encoding)
      @row_separator =
        resolve_row_separator(@options[:row_separator]).encode(@encoding)
      @quote_character = @options[:quote_character].to_s.encode(@encoding)
      if @quote_character.length != 1
        raise ArgumentError, ":quote_char has to be a single character String"
      end

      escaped_column_separator = Regexp.escape(@column_separator)
      escaped_row_separator = Regexp.escape(@row_separator)
      escaped_quote_character = Regexp.escape(@quote_character)

      skip_lines = @options[:skip_lines]
      case skip_lines
      when String
        @skip_lines = skip_lines.encode(@encoding)
      when Regexp, nil
        @skip_lines = skip_lines
      else
        unless skip_lines.respond_to?(:match)
          message =
            ":skip_lines has to respond to \#match: #{skip_lines.inspect}"
          raise ArgumentError, message
        end
        @skip_lines = skip_lines
      end

      @column_end = Regexp.new(escaped_column_separator)
      if @column_separator.size > 1
        @column_ends = @column_separator.each_char.collect do |char|
          Regexp.new(Regexp.escape(char))
        end
      else
        @column_ends = nil
      end
      @row_end = Regexp.new(escaped_row_separator)
      if @row_separator.size > 1
        @row_ends = @row_separator.each_char.collect do |char|
          Regexp.new(Regexp.escape(char))
        end
      else
        @row_ends = nil
      end
      @quotes = Regexp.new(escaped_quote_character +
                           "+".encode(@encoding))
      @quoted_value = Regexp.new("[^".encode(@encoding) +
                                 escaped_quote_character +
                                 "]+".encode(@encoding))
      if @liberal_parsing
        @unquoted_value = Regexp.new("[^".encode(@encoding) +
                                     escaped_column_separator +
                                     "\r\n]+".encode(@encoding))
      else
        @unquoted_value = Regexp.new("[^".encode(@encoding) +
                                     escaped_quote_character +
                                     escaped_column_separator +
                                     "\r\n]+".encode(@encoding))
      end
      @cr_or_lf = Regexp.new("[\r\n]".encode(@encoding))
      @not_line_end = Regexp.new("[^\r\n]+".encode(@encoding))
    end

    def resolve_row_separator(separator)
      if separator == :auto
        cr = "\r".encode(@encoding)
        lf = "\n".encode(@encoding)
        if @input.is_a?(StringIO)
          separator = detect_row_separator(@input.string, cr, lf)
        elsif @input.respond_to?(:gets)
          if @input.is_a?(File)
            chunk_size = 32 * 1024
          else
            chunk_size = 1024
          end
          begin
            while separator == :auto
              #
              # if we run out of data, it's probably a single line
              # (ensure will set default value)
              #
              break unless sample = @input.gets(nil, chunk_size)

              # extend sample if we're unsure of the line ending
              if sample.end_with?(cr)
                sample << (@input.gets(nil, 1) || "")
              end

              @samples << sample

              separator = detect_row_separator(sample, cr, lf)
            end
          rescue IOError
            # do nothing:  ensure will set default
          end
        end
        separator = $INPUT_RECORD_SEPARATOR if separator == :auto
      end
      separator.to_s.encode(@encoding)
    end

    def detect_row_separator(sample, cr, lf)
      lf_index = sample.index(lf)
      if lf_index
        cr_index = sample[0, lf_index].index(cr)
      else
        cr_index = sample.index(cr)
      end
      if cr_index and lf_index
        if cr_index + 1 == lf_index
          cr + lf
        elsif cr_index < lf_index
          cr
        else
          lf
        end
      elsif cr_index
        cr
      elsif lf_index
        lf
      else
        :auto
      end
    end

    def prepare_line
      @lineno = 0
      @last_line = nil
      @scanner = nil
    end

    def last_line
      if @scanner
        @last_line ||= @scanner.keep_end
      else
        @last_line
      end
    end

    def prepare_header
      @return_headers = @options[:return_headers]

      headers = @options[:headers]
      case headers
      when Array
        @raw_headers = headers
        @use_headers = true
      when String
        @raw_headers = parse_headers(headers)
        @use_headers = true
      when nil, false
        @raw_headers = nil
        @use_headers = false
      else
        @raw_headers = nil
        @use_headers = true
      end
      if @raw_headers
        @headers = adjust_headers(@raw_headers)
      else
        @headers = nil
      end
    end

    def parse_headers(row)
      CSV.parse_line(row,
                     col_sep:    @column_separator,
                     row_sep:    @row_separator,
                     quote_char: @quote_character)
    end

    def adjust_headers(headers)
      adjusted_headers = @header_fields_converter.convert(headers, nil, @lineno)
      adjusted_headers.each {|h| h.freeze if h.is_a? String}
      adjusted_headers
    end

    def prepare_parser
      @may_quoted = may_quoted?
    end

    def may_quoted?
      if @input.is_a?(StringIO)
        sample = @input.string
      else
        return false if @samples.empty?
        sample = @samples.first
      end
      sample[0, 128].index(@quote_character)
    end

    SCANNER_TEST = (ENV["CSV_PARSER_SCANNER_TEST"] == "yes")
    if SCANNER_TEST
      class UnoptimizedStringIO
        def initialize(string)
          @io = StringIO.new(string)
        end

        def gets(*args)
          @io.gets(*args)
        end

        def eof?
          @io.eof?
        end
      end

      def build_scanner
        inputs = @samples.collect do |sample|
          UnoptimizedStringIO.new(sample)
        end
        if @input.is_a?(StringIO)
          inputs << UnoptimizedStringIO.new(@input.string)
        else
          inputs << @input
        end
        InputsScanner.new(inputs, @encoding, chunk_size: 1)
      end
    else
      def build_scanner
        string = nil
        if @samples.empty? and @input.is_a?(StringIO)
          string = @input.string
        elsif @samples.size == 1 and @input.respond_to?(:eof?) and @input.eof?
          string = @samples[0]
        end
        if string
          unless string.valid_encoding?
            message = "Invalid byte sequence in #{@encoding}"
            raise MalformedCSVError.new(message, @lineno + 1)
          end
          Scanner.new(string)
        else
          inputs = @samples.collect do |sample|
            StringIO.new(sample)
          end
          inputs << @input
          InputsScanner.new(inputs, @encoding)
        end
      end
    end

    def skip_needless_lines
      return unless @skip_lines

      while true
        @scanner.keep_start
        line = @scanner.scan_all(@not_line_end) || "".encode(@encoding)
        line << @row_separator if parse_row_end
        if skip_line?(line)
          @scanner.keep_drop
        else
          @scanner.keep_back
          return
        end
      end
    end

    def skip_line?(line)
      case @skip_lines
      when String
        line.include?(@skip_lines)
      when Regexp
        @skip_lines.match?(line)
      else
        @skip_lines.match(line)
      end
    end

    def parse_column_value
      if @liberal_parsing
        quoted_value = parse_quoted_column_value
        if quoted_value
          unquoted_value = parse_unquoted_column_value
          if unquoted_value
            @quote_character + quoted_value + @quote_character + unquoted_value
          else
            quoted_value
          end
        else
          parse_unquoted_column_value
        end
      elsif @may_quoted
        parse_quoted_column_value ||
          parse_unquoted_column_value
      else
        parse_unquoted_column_value ||
          parse_quoted_column_value
      end
    end

    def parse_unquoted_column_value
      value = @scanner.scan_all(@unquoted_value)
      @unquoted_column_value = true if value
      value
    end

    def parse_quoted_column_value
      quotes = @scanner.scan_all(@quotes)
      return nil unless quotes

      @quoted_column_value = true
      n_quotes = quotes.size
      if (n_quotes % 2).zero?
        quotes[0, (n_quotes - 2) / 2]
      else
        value = quotes[0, (n_quotes - 1) / 2]
        while true
          quoted_value = @scanner.scan_all(@quoted_value)
          value << quoted_value if quoted_value
          quotes = @scanner.scan_all(@quotes)
          unless quotes
            message = "Unclosed quoted field"
            raise MalformedCSVError.new(message, @lineno + 1)
          end
          n_quotes = quotes.size
          if n_quotes == 1
            break
          elsif (n_quotes % 2) == 1
            value << quotes[0, (n_quotes - 1) / 2]
            break
          else
            value << quotes[0, n_quotes / 2]
          end
        end
        value
      end
    end

    def parse_column_end
      return true if @scanner.scan(@column_end)
      return false unless @column_ends

      @scanner.keep_start
      if @column_ends.all? {|column_end| @scanner.scan(column_end)}
        @scanner.keep_drop
        true
      else
        @scanner.keep_back
        false
      end
    end

    def parse_row_end
      return true if @scanner.scan(@row_end)
      return false unless @row_ends
      @scanner.keep_start
      if @row_ends.all? {|row_end| @scanner.scan(row_end)}
        @scanner.keep_drop
        true
      else
        @scanner.keep_back
        false
      end
    end

    def start_row
      if @last_line
        @last_line = nil
      else
        @scanner.keep_drop
      end
      @scanner.keep_start
    end

    def emit_row(row, &block)
      @lineno += 1

      raw_row = row
      if @use_headers
        if @headers.nil?
          @headers = adjust_headers(row)
          return unless @return_headers
          row = Row.new(@headers, row, true)
        else
          row = Row.new(@headers,
                        @fields_converter.convert(raw_row, @headers, @lineno))
        end
      else
        # convert fields, if needed...
        row = @fields_converter.convert(raw_row, nil, @lineno)
      end

      # inject unconverted fields and accessor, if requested...
      if @unconverted_fields and not row.respond_to?(:unconverted_fields)
        add_unconverted_fields(row, raw_row)
      end

      yield(row)
    end

    # This method injects an instance variable <tt>unconverted_fields</tt> into
    # +row+ and an accessor method for +row+ called unconverted_fields().  The
    # variable is set to the contents of +fields+.
    def add_unconverted_fields(row, fields)
      class << row
        attr_reader :unconverted_fields
      end
      row.instance_variable_set(:@unconverted_fields, fields)
      row
    end
  end
end
