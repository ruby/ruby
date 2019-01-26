# frozen_string_literal: true

require_relative "match_p"
require_relative "row"

using CSV::MatchP if CSV.const_defined?(:MatchP)

class CSV
  class Writer
    attr_reader :lineno
    attr_reader :headers

    def initialize(output, options)
      @output = output
      @options = options
      @lineno = 0
      prepare
      if @options[:write_headers] and @headers
        self << @headers
      end
    end

    def <<(row)
      case row
      when Row
        row = row.fields
      when Hash
        row = @headers.collect {|header| row[header]}
      end

      @headers ||= row if @use_headers
      @lineno += 1

      converted_row = row.collect do |field|
        quote(field)
      end
      line = converted_row.join(@column_separator) + @row_separator
      if @output_encoding
        line = line.encode(@output_encoding)
      end
      @output << line

      self
    end

    def rewind
      @lineno = 0
      @headers = nil if @options[:headers].nil?
    end

    private
    def prepare
      @encoding = @options[:encoding]

      prepare_header
      prepare_format
      prepare_output
    end

    def prepare_header
      headers = @options[:headers]
      case headers
      when Array
        @headers = headers
        @use_headers = true
      when String
        @headers = CSV.parse_line(headers,
                                  col_sep: @options[:column_separator],
                                  row_sep: @options[:row_separator],
                                  quote_char: @options[:quote_character])
        @use_headers = true
      when true
        @headers = nil
        @use_headers = true
      else
        @headers = nil
        @use_headers = false
      end
      return unless @headers

      converter = @options[:header_fields_converter]
      @headers = converter.convert(@headers, nil, 0)
      @headers.each do |header|
        header.freeze if header.is_a?(String)
      end
    end

    def prepare_format
      @column_separator = @options[:column_separator].to_s.encode(@encoding)
      row_separator = @options[:row_separator]
      if row_separator == :auto
        @row_separator = $INPUT_RECORD_SEPARATOR.encode(@encoding)
      else
        @row_separator = row_separator.to_s.encode(@encoding)
      end
      @quote_character = @options[:quote_character]
      @force_quotes = @options[:force_quotes]
      unless @force_quotes
        @quotable_pattern =
          Regexp.new("[\r\n".encode(@encoding) +
                     Regexp.escape(@column_separator) +
                     Regexp.escape(@quote_character.encode(@encoding)) +
                     "]".encode(@encoding))
      end
      @quote_empty = @options.fetch(:quote_empty, true)
    end

    def prepare_output
      @output_encoding = nil
      return unless @output.is_a?(StringIO)

      output_encoding = @output.internal_encoding || @output.external_encoding
      if @encoding != output_encoding
        if @options[:force_encoding]
          @output_encoding = output_encoding
        else
          compatible_encoding = Encoding.compatible?(@encoding, output_encoding)
          if compatible_encoding
            @output.set_encoding(compatible_encoding)
            @output.seek(0, IO::SEEK_END)
          end
        end
      end
    end

    def quote_field(field)
      field = String(field)
      encoded_quote_character = @quote_character.encode(field.encoding)
      encoded_quote_character +
        field.gsub(encoded_quote_character,
                   encoded_quote_character * 2) +
        encoded_quote_character
    end

    def quote(field)
      if @force_quotes
        quote_field(field)
      else
        if field.nil?  # represent +nil+ fields as empty unquoted fields
          ""
        else
          field = String(field)  # Stringify fields
          # represent empty fields as empty quoted fields
          if (@quote_empty and field.empty?) or @quotable_pattern.match?(field)
            quote_field(field)
          else
            field  # unquoted field
          end
        end
      end
    end
  end
end
