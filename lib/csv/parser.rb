# frozen_string_literal: true

require "strscan"

require_relative "delete_suffix"
require_relative "match_p"
require_relative "row"
require_relative "table"

using CSV::DeleteSuffix if CSV.const_defined?(:DeleteSuffix)
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

      def each_line(row_separator)
        position = pos
        rest.each_line(row_separator) do |line|
          position += line.bytesize
          self.pos = position
          yield(line)
        end
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

      def each_line(row_separator)
        buffer = nil
        input = @scanner.rest
        position = @scanner.pos
        offset = 0
        n_row_separator_chars = row_separator.size
        while true
          input.each_line(row_separator) do |line|
            @scanner.pos += line.bytesize
            if buffer
              if n_row_separator_chars == 2 and
                buffer.end_with?(row_separator[0]) and
                line.start_with?(row_separator[1])
                buffer << line[0]
                line = line[1..-1]
                position += buffer.bytesize + offset
                @scanner.pos = position
                offset = 0
                yield(buffer)
                buffer = nil
                next if line.empty?
              else
                buffer << line
                line = buffer
                buffer = nil
              end
            end
            if line.end_with?(row_separator)
              position += line.bytesize + offset
              @scanner.pos = position
              offset = 0
              yield(line)
            else
              buffer = line
            end
          end
          break unless read_chunk
          input = @scanner.rest
          position = @scanner.pos
          offset = -buffer.bytesize if buffer
        end
        yield(buffer) if buffer
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
          keep = string.byteslice(start, string.bytesize - start)
          if keep and not keep.empty?
            @inputs.unshift(StringIO.new(keep))
            @last_scanner = false
          end
          @scanner = StringScanner.new(buffer)
        else
          @scanner.pos = start
        end
        read_chunk if @scanner.eos?
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
          keep_data = string.byteslice(keep_start, @scanner.pos - keep_start)
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

      if @return_headers and @headers and @raw_headers
        headers = Row.new(@headers, @raw_headers, true)
        if @unconverted_fields
          headers = add_unconverted_fields(headers, [])
        end
        yield headers
      end

      begin
        @scanner ||= build_scanner
        if quote_character.nil?
          parse_no_quote(&block)
        elsif @need_robust_parsing
          parse_quotable_robust(&block)
        else
          parse_quotable_loose(&block)
        end
      rescue InvalidEncoding
        if @scanner
          ignore_broken_line
          lineno = @lineno
        else
          lineno = @lineno + 1
        end
        message = "Invalid byte sequence in #{@encoding}"
        raise MalformedCSVError.new(message, lineno)
      end
    end

    def use_headers?
      @use_headers
    end

    private
    def prepare
      prepare_variable
      prepare_quote_character
      prepare_backslash
      prepare_skip_lines
      prepare_strip
      prepare_separators
      prepare_quoted
      prepare_unquoted
      prepare_line
      prepare_header
      prepare_parser
    end

    def prepare_variable
      @need_robust_parsing = false
      @encoding = @options[:encoding]
      liberal_parsing = @options[:liberal_parsing]
      if liberal_parsing
        @liberal_parsing = true
        if liberal_parsing.is_a?(Hash)
          @double_quote_outside_quote =
            liberal_parsing[:double_quote_outside_quote]
          @backslash_quote = liberal_parsing[:backslash_quote]
        else
          @double_quote_outside_quote = false
          @backslash_quote = false
        end
        @need_robust_parsing = true
      else
        @liberal_parsing = false
        @backslash_quote = false
      end
      @unconverted_fields = @options[:unconverted_fields]
      @field_size_limit = @options[:field_size_limit]
      @skip_blanks = @options[:skip_blanks]
      @fields_converter = @options[:fields_converter]
      @header_fields_converter = @options[:header_fields_converter]
    end

    def prepare_quote_character
      @quote_character = @options[:quote_character]
      if @quote_character.nil?
        @escaped_quote_character = nil
        @escaped_quote = nil
      else
        @quote_character = @quote_character.to_s.encode(@encoding)
        if @quote_character.length != 1
          message = ":quote_char has to be nil or a single character String"
          raise ArgumentError, message
        end
        @double_quote_character = @quote_character * 2
        @escaped_quote_character = Regexp.escape(@quote_character)
        @escaped_quote = Regexp.new(@escaped_quote_character)
      end
    end

    def prepare_backslash
      return unless @backslash_quote

      @backslash_character = "\\".encode(@encoding)

      @escaped_backslash_character = Regexp.escape(@backslash_character)
      @escaped_backslash = Regexp.new(@escaped_backslash_character)
      if @quote_character.nil?
        @backslash_quote_character = nil
      else
        @backslash_quote_character =
          @backslash_character + @escaped_quote_character
      end
    end

    def prepare_skip_lines
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
    end

    def prepare_strip
      @strip = @options[:strip]
      @escaped_strip = nil
      @strip_value = nil
      if @strip.is_a?(String)
        case @strip.length
        when 0
          raise ArgumentError, ":strip must not be an empty String"
        when 1
          # ok
        else
          raise ArgumentError, ":strip doesn't support 2 or more characters yet"
        end
        @strip = @strip.encode(@encoding)
        @escaped_strip = Regexp.escape(@strip)
        if @quote_character
          @strip_value = Regexp.new(@escaped_strip +
                                    "+".encode(@encoding))
        end
        @need_robust_parsing = true
      elsif @strip
        strip_values = " \t\f\v"
        @escaped_strip = strip_values.encode(@encoding)
        if @quote_character
          @strip_value = Regexp.new("[#{strip_values}]+".encode(@encoding))
        end
        @need_robust_parsing = true
      end
    end

    begin
      StringScanner.new("x").scan("x")
    rescue TypeError
      @@string_scanner_scan_accept_string = false
    else
      @@string_scanner_scan_accept_string = true
    end

    def prepare_separators
      @column_separator = @options[:column_separator].to_s.encode(@encoding)
      @row_separator =
        resolve_row_separator(@options[:row_separator]).encode(@encoding)

      @escaped_column_separator = Regexp.escape(@column_separator)
      @escaped_first_column_separator = Regexp.escape(@column_separator[0])
      if @column_separator.size > 1
        @column_end = Regexp.new(@escaped_column_separator)
        @column_ends = @column_separator.each_char.collect do |char|
          Regexp.new(Regexp.escape(char))
        end
        @first_column_separators = Regexp.new(@escaped_first_column_separator +
                                              "+".encode(@encoding))
      else
        if @@string_scanner_scan_accept_string
          @column_end = @column_separator
        else
          @column_end = Regexp.new(@escaped_column_separator)
        end
        @column_ends = nil
        @first_column_separators = nil
      end

      escaped_row_separator = Regexp.escape(@row_separator)
      @row_end = Regexp.new(escaped_row_separator)
      if @row_separator.size > 1
        @row_ends = @row_separator.each_char.collect do |char|
          Regexp.new(Regexp.escape(char))
        end
      else
        @row_ends = nil
      end

      @cr = "\r".encode(@encoding)
      @lf = "\n".encode(@encoding)
      @cr_or_lf = Regexp.new("[\r\n]".encode(@encoding))
      @not_line_end = Regexp.new("[^\r\n]+".encode(@encoding))
    end

    def prepare_quoted
      if @quote_character
        @quotes = Regexp.new(@escaped_quote_character +
                             "+".encode(@encoding))
        no_quoted_values = @escaped_quote_character.dup
        if @backslash_quote
          no_quoted_values << @escaped_backslash_character
        end
        @quoted_value = Regexp.new("[^".encode(@encoding) +
                                   no_quoted_values +
                                   "]+".encode(@encoding))
      end
      if @escaped_strip
        @split_column_separator = Regexp.new(@escaped_strip +
                                             "*".encode(@encoding) +
                                             @escaped_column_separator +
                                             @escaped_strip +
                                             "*".encode(@encoding))
      else
        if @column_separator == " ".encode(@encoding)
          @split_column_separator = Regexp.new(@escaped_column_separator)
        else
          @split_column_separator = @column_separator
        end
      end
    end

    def prepare_unquoted
      return if @quote_character.nil?

      no_unquoted_values = "\r\n".encode(@encoding)
      no_unquoted_values << @escaped_first_column_separator
      unless @liberal_parsing
        no_unquoted_values << @escaped_quote_character
      end
      if @escaped_strip
        no_unquoted_values << @escaped_strip
      end
      @unquoted_value = Regexp.new("[^".encode(@encoding) +
                                   no_unquoted_values +
                                   "]+".encode(@encoding))
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
      return false if @quote_character.nil?

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

        def each_line(*args, &block)
          @io.each_line(*args, &block)
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
        chunk_size = ENV["CSV_PARSER_SCANNER_TEST_CHUNK_SIZE"] || "1"
        InputsScanner.new(inputs,
                          @encoding,
                          chunk_size: Integer(chunk_size, 10))
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
            index = string.lines(@row_separator).index do |line|
              !line.valid_encoding?
            end
            if index
              message = "Invalid byte sequence in #{@encoding}"
              raise MalformedCSVError.new(message, @lineno + index + 1)
            end
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
          @lineno += 1
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

    def parse_no_quote(&block)
      @scanner.each_line(@row_separator) do |line|
        next if @skip_lines and skip_line?(line)
        original_line = line
        line = line.delete_suffix(@row_separator)

        if line.empty?
          next if @skip_blanks
          row = []
        else
          line = strip_value(line)
          row = line.split(@split_column_separator, -1)
          n_columns = row.size
          i = 0
          while i < n_columns
            row[i] = nil if row[i].empty?
            i += 1
          end
        end
        @last_line = original_line
        emit_row(row, &block)
      end
    end

    def parse_quotable_loose(&block)
      @scanner.keep_start
      @scanner.each_line(@row_separator) do |line|
        if @skip_lines and skip_line?(line)
          @scanner.keep_drop
          @scanner.keep_start
          next
        end
        original_line = line
        line = line.delete_suffix(@row_separator)

        if line.empty?
          if @skip_blanks
            @scanner.keep_drop
            @scanner.keep_start
            next
          end
          row = []
        elsif line.include?(@cr) or line.include?(@lf)
          @scanner.keep_back
          @need_robust_parsing = true
          return parse_quotable_robust(&block)
        else
          row = line.split(@split_column_separator, -1)
          n_columns = row.size
          i = 0
          while i < n_columns
            column = row[i]
            if column.empty?
              row[i] = nil
            else
              n_quotes = column.count(@quote_character)
              if n_quotes.zero?
                # no quote
              elsif n_quotes == 2 and
                   column.start_with?(@quote_character) and
                   column.end_with?(@quote_character)
                row[i] = column[1..-2]
              else
                @scanner.keep_back
                @need_robust_parsing = true
                return parse_quotable_robust(&block)
              end
            end
            i += 1
          end
        end
        @scanner.keep_drop
        @scanner.keep_start
        @last_line = original_line
        emit_row(row, &block)
      end
      @scanner.keep_drop
    end

    def parse_quotable_robust(&block)
      row = []
      skip_needless_lines
      start_row
      while true
        @quoted_column_value = false
        @unquoted_column_value = false
        @scanner.scan_all(@strip_value) if @strip_value
        value = parse_column_value
        if value
          @scanner.scan_all(@strip_value) if @strip_value
          if @field_size_limit and value.size >= @field_size_limit
            ignore_broken_line
            raise MalformedCSVError.new("Field size exceeded", @lineno)
          end
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
          break if row.empty? and value.nil?
          row << value
          emit_row(row, &block)
          break
        else
          if @quoted_column_value
            ignore_broken_line
            message = "Any value after quoted field isn't allowed"
            raise MalformedCSVError.new(message, @lineno)
          elsif @unquoted_column_value and
                (new_line = @scanner.scan(@cr_or_lf))
            ignore_broken_line
            message = "Unquoted fields do not allow new line " +
                      "<#{new_line.inspect}>"
            raise MalformedCSVError.new(message, @lineno)
          elsif @scanner.rest.start_with?(@quote_character)
            ignore_broken_line
            message = "Illegal quoting"
            raise MalformedCSVError.new(message, @lineno)
          elsif (new_line = @scanner.scan(@cr_or_lf))
            ignore_broken_line
            message = "New line must be <#{@row_separator.inspect}> " +
                      "not <#{new_line.inspect}>"
            raise MalformedCSVError.new(message, @lineno)
          else
            ignore_broken_line
            raise MalformedCSVError.new("TODO: Meaningful message",
                                        @lineno)
          end
        end
      end
    end

    def parse_column_value
      if @liberal_parsing
        quoted_value = parse_quoted_column_value
        if quoted_value
          unquoted_value = parse_unquoted_column_value
          if unquoted_value
            if @double_quote_outside_quote
              unquoted_value = unquoted_value.gsub(@quote_character * 2,
                                                   @quote_character)
              if quoted_value.empty? # %Q{""...} case
                return @quote_character + unquoted_value
              end
            end
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
      return nil unless value

      @unquoted_column_value = true
      if @first_column_separators
        while true
          @scanner.keep_start
          is_column_end = @column_ends.all? do |column_end|
            @scanner.scan(column_end)
          end
          @scanner.keep_back
          break if is_column_end
          sub_separator = @scanner.scan_all(@first_column_separators)
          break if sub_separator.nil?
          value << sub_separator
          sub_value = @scanner.scan_all(@unquoted_value)
          break if sub_value.nil?
          value << sub_value
        end
      end
      value.gsub!(@backslash_quote_character, @quote_character) if @backslash_quote
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
          if @backslash_quote
            if @scanner.scan(@escaped_backslash)
              if @scanner.scan(@escaped_quote)
                value << @quote_character
              else
                value << @backslash_character
              end
              next
            end
          end

          quotes = @scanner.scan_all(@quotes)
          unless quotes
            ignore_broken_line
            message = "Unclosed quoted field"
            raise MalformedCSVError.new(message, @lineno)
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

    def strip_value(value)
      return value unless @strip
      return nil if value.nil?

      case @strip
      when String
        size = value.size
        while value.start_with?(@strip)
          size -= 1
          value = value[1, size]
        end
        while value.end_with?(@strip)
          size -= 1
          value = value[0, size]
        end
      else
        value.strip!
      end
      value
    end

    def ignore_broken_line
      @scanner.scan_all(@not_line_end)
      @scanner.scan_all(@cr_or_lf)
      @lineno += 1
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
