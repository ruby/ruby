# encoding: US-ASCII
# frozen_string_literal: true
# = csv.rb -- CSV Reading and Writing
#
# Created by James Edward Gray II on 2005-10-31.
#
# See CSV for documentation.
#
# == Description
#
# Welcome to the new and improved CSV.
#
# This version of the CSV library began its life as FasterCSV.  FasterCSV was
# intended as a replacement to Ruby's then standard CSV library.  It was
# designed to address concerns users of that library had and it had three
# primary goals:
#
# 1.  Be significantly faster than CSV while remaining a pure Ruby library.
# 2.  Use a smaller and easier to maintain code base.  (FasterCSV eventually
#     grew larger, was also but considerably richer in features.  The parsing
#     core remains quite small.)
# 3.  Improve on the CSV interface.
#
# Obviously, the last one is subjective.  I did try to defer to the original
# interface whenever I didn't have a compelling reason to change it though, so
# hopefully this won't be too radically different.
#
# We must have met our goals because FasterCSV was renamed to CSV and replaced
# the original library as of Ruby 1.9. If you are migrating code from 1.8 or
# earlier, you may have to change your code to comply with the new interface.
#
# == What's Different From the Old CSV?
#
# I'm sure I'll miss something, but I'll try to mention most of the major
# differences I am aware of, to help others quickly get up to speed:
#
# === CSV Parsing
#
# * This parser is m17n aware.  See CSV for full details.
# * This library has a stricter parser and will throw MalformedCSVErrors on
#   problematic data.
# * This library has a less liberal idea of a line ending than CSV.  What you
#   set as the <tt>:row_sep</tt> is law.  It can auto-detect your line endings
#   though.
# * The old library returned empty lines as <tt>[nil]</tt>.  This library calls
#   them <tt>[]</tt>.
# * This library has a much faster parser.
#
# === Interface
#
# * CSV now uses Hash-style parameters to set options.
# * CSV no longer has generate_row() or parse_row().
# * The old CSV's Reader and Writer classes have been dropped.
# * CSV::open() is now more like Ruby's open().
# * CSV objects now support most standard IO methods.
# * CSV now has a new() method used to wrap objects like String and IO for
#   reading and writing.
# * CSV::generate() is different from the old method.
# * CSV no longer supports partial reads.  It works line-by-line.
# * CSV no longer allows the instance methods to override the separators for
#   performance reasons.  They must be set in the constructor.
#
# If you use this library and find yourself missing any functionality I have
# trimmed, please {let me know}[mailto:james@grayproductions.net].
#
# == Documentation
#
# See CSV for documentation.
#
# == What is CSV, really?
#
# CSV maintains a pretty strict definition of CSV taken directly from
# {the RFC}[http://www.ietf.org/rfc/rfc4180.txt].  I relax the rules in only one
# place and that is to make using this library easier.  CSV will parse all valid
# CSV.
#
# What you don't want to do is feed CSV invalid data.  Because of the way the
# CSV format works, it's common for a parser to need to read until the end of
# the file to be sure a field is invalid.  This eats a lot of time and memory.
#
# Luckily, when working with invalid CSV, Ruby's built-in methods will almost
# always be superior in every way.  For example, parsing non-quoted fields is as
# easy as:
#
#   data.split(",")
#
# == Questions and/or Comments
#
# Feel free to email {James Edward Gray II}[mailto:james@grayproductions.net]
# with any questions.

require "forwardable"
require "English"
require "date"
require "stringio"

require_relative "csv/fields_converter"
require_relative "csv/match_p"
require_relative "csv/parser"
require_relative "csv/row"
require_relative "csv/table"
require_relative "csv/writer"

using CSV::MatchP if CSV.const_defined?(:MatchP)

#
# This class provides a complete interface to CSV files and data.  It offers
# tools to enable you to read and write to and from Strings or IO objects, as
# needed.
#
# The most generic interface of the library is:
#
#    csv = CSV.new(string_or_io, **options)
#
#    # Reading: IO object should be open for read
#    csv.read # => array of rows
#    # or
#    csv.each do |row|
#      # ...
#    end
#    # or
#    row = csv.shift
#
#    # Writing: IO object should be open for write
#    csv << row
#
# There are several specialized class methods for one-statement reading or writing,
# described in the Specialized Methods section.
#
# If a String is passed into ::new, it is internally wrapped into a StringIO object.
#
# +options+ can be used for specifying the particular CSV flavor (column
# separators, row separators, value quoting and so on), and for data conversion,
# see Data Conversion section for the description of the latter.
#
# == Specialized Methods
#
# === Reading
#
#   # From a file: all at once
#   arr_of_rows = CSV.read("path/to/file.csv", **options)
#   # iterator-style:
#   CSV.foreach("path/to/file.csv", **options) do |row|
#     # ...
#   end
#
#   # From a string
#   arr_of_rows = CSV.parse("CSV,data,String", **options)
#   # or
#   CSV.parse("CSV,data,String", **options) do |row|
#     # ...
#   end
#
# === Writing
#
#   # To a file
#   CSV.open("path/to/file.csv", "wb") do |csv|
#     csv << ["row", "of", "CSV", "data"]
#     csv << ["another", "row"]
#     # ...
#   end
#
#   # To a String
#   csv_string = CSV.generate do |csv|
#     csv << ["row", "of", "CSV", "data"]
#     csv << ["another", "row"]
#     # ...
#   end
#
# === Shortcuts
#
#   # Core extensions for converting one line
#   csv_string = ["CSV", "data"].to_csv   # to CSV
#   csv_array  = "CSV,String".parse_csv   # from CSV
#
#   # CSV() method
#   CSV             { |csv_out| csv_out << %w{my data here} }  # to $stdout
#   CSV(csv = "")   { |csv_str| csv_str << %w{my data here} }  # to a String
#   CSV($stderr)    { |csv_err| csv_err << %w{my data here} }  # to $stderr
#   CSV($stdin)     { |csv_in|  csv_in.each { |row| p row } }  # from $stdin
#
# == Data Conversion
#
# === CSV with headers
#
# CSV allows to specify column names of CSV file, whether they are in data, or
# provided separately. If headers specified, reading methods return an instance
# of CSV::Table, consisting of CSV::Row.
#
#   # Headers are part of data
#   data = CSV.parse(<<~ROWS, headers: true)
#     Name,Department,Salary
#     Bob,Engineering,1000
#     Jane,Sales,2000
#     John,Management,5000
#   ROWS
#
#   data.class      #=> CSV::Table
#   data.first      #=> #<CSV::Row "Name":"Bob" "Department":"Engineering" "Salary":"1000">
#   data.first.to_h #=> {"Name"=>"Bob", "Department"=>"Engineering", "Salary"=>"1000"}
#
#   # Headers provided by developer
#   data = CSV.parse('Bob,Engeneering,1000', headers: %i[name department salary])
#   data.first      #=> #<CSV::Row name:"Bob" department:"Engineering" salary:"1000">
#
# === Typed data reading
#
# CSV allows to provide a set of data _converters_ e.g. transformations to try on input
# data. Converter could be a symbol from CSV::Converters constant's keys, or lambda.
#
#   # Without any converters:
#   CSV.parse('Bob,2018-03-01,100')
#   #=> [["Bob", "2018-03-01", "100"]]
#
#   # With built-in converters:
#   CSV.parse('Bob,2018-03-01,100', converters: %i[numeric date])
#   #=> [["Bob", #<Date: 2018-03-01>, 100]]
#
#   # With custom converters:
#   CSV.parse('Bob,2018-03-01,100', converters: [->(v) { Time.parse(v) rescue v }])
#   #=> [["Bob", 2018-03-01 00:00:00 +0200, "100"]]
#
# == CSV and Character Encodings (M17n or Multilingualization)
#
# This new CSV parser is m17n savvy.  The parser works in the Encoding of the IO
# or String object being read from or written to.  Your data is never transcoded
# (unless you ask Ruby to transcode it for you) and will literally be parsed in
# the Encoding it is in.  Thus CSV will return Arrays or Rows of Strings in the
# Encoding of your data.  This is accomplished by transcoding the parser itself
# into your Encoding.
#
# Some transcoding must take place, of course, to accomplish this multiencoding
# support.  For example, <tt>:col_sep</tt>, <tt>:row_sep</tt>, and
# <tt>:quote_char</tt> must be transcoded to match your data.  Hopefully this
# makes the entire process feel transparent, since CSV's defaults should just
# magically work for your data.  However, you can set these values manually in
# the target Encoding to avoid the translation.
#
# It's also important to note that while all of CSV's core parser is now
# Encoding agnostic, some features are not.  For example, the built-in
# converters will try to transcode data to UTF-8 before making conversions.
# Again, you can provide custom converters that are aware of your Encodings to
# avoid this translation.  It's just too hard for me to support native
# conversions in all of Ruby's Encodings.
#
# Anyway, the practical side of this is simple:  make sure IO and String objects
# passed into CSV have the proper Encoding set and everything should just work.
# CSV methods that allow you to open IO objects (CSV::foreach(), CSV::open(),
# CSV::read(), and CSV::readlines()) do allow you to specify the Encoding.
#
# One minor exception comes when generating CSV into a String with an Encoding
# that is not ASCII compatible.  There's no existing data for CSV to use to
# prepare itself and thus you will probably need to manually specify the desired
# Encoding for most of those cases.  It will try to guess using the fields in a
# row of output though, when using CSV::generate_line() or Array#to_csv().
#
# I try to point out any other Encoding issues in the documentation of methods
# as they come up.
#
# This has been tested to the best of my ability with all non-"dummy" Encodings
# Ruby ships with.  However, it is brave new code and may have some bugs.
# Please feel free to {report}[mailto:james@grayproductions.net] any issues you
# find with it.
#
class CSV

  # The error thrown when the parser encounters illegal CSV formatting.
  class MalformedCSVError < RuntimeError
    attr_reader :line_number
    alias_method :lineno, :line_number
    def initialize(message, line_number)
      @line_number = line_number
      super("#{message} in line #{line_number}.")
    end
  end

  #
  # A FieldInfo Struct contains details about a field's position in the data
  # source it was read from.  CSV will pass this Struct to some blocks that make
  # decisions based on field structure.  See CSV.convert_fields() for an
  # example.
  #
  # <b><tt>index</tt></b>::  The zero-based index of the field in its row.
  # <b><tt>line</tt></b>::   The line of the data source this row is from.
  # <b><tt>header</tt></b>:: The header for the column, when available.
  #
  FieldInfo = Struct.new(:index, :line, :header)

  # A Regexp used to find and convert some common Date formats.
  DateMatcher     = / \A(?: (\w+,?\s+)?\w+\s+\d{1,2},?\s+\d{2,4} |
                            \d{4}-\d{2}-\d{2} )\z /x
  # A Regexp used to find and convert some common DateTime formats.
  DateTimeMatcher =
    / \A(?: (\w+,?\s+)?\w+\s+\d{1,2}\s+\d{1,2}:\d{1,2}:\d{1,2},?\s+\d{2,4} |
            \d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2} |
            # ISO-8601
            \d{4}-\d{2}-\d{2}
              (?:T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?(?:[+-]\d{2}(?::\d{2})|Z)?)?)?
        )\z /x

  # The encoding used by all converters.
  ConverterEncoding = Encoding.find("UTF-8")

  #
  # This Hash holds the built-in converters of CSV that can be accessed by name.
  # You can select Converters with CSV.convert() or through the +options+ Hash
  # passed to CSV::new().
  #
  # <b><tt>:integer</tt></b>::    Converts any field Integer() accepts.
  # <b><tt>:float</tt></b>::      Converts any field Float() accepts.
  # <b><tt>:numeric</tt></b>::    A combination of <tt>:integer</tt>
  #                               and <tt>:float</tt>.
  # <b><tt>:date</tt></b>::       Converts any field Date::parse() accepts.
  # <b><tt>:date_time</tt></b>::  Converts any field DateTime::parse() accepts.
  # <b><tt>:all</tt></b>::        All built-in converters.  A combination of
  #                               <tt>:date_time</tt> and <tt>:numeric</tt>.
  #
  # All built-in converters transcode field data to UTF-8 before attempting a
  # conversion.  If your data cannot be transcoded to UTF-8 the conversion will
  # fail and the field will remain unchanged.
  #
  # This Hash is intentionally left unfrozen and users should feel free to add
  # values to it that can be accessed by all CSV objects.
  #
  # To add a combo field, the value should be an Array of names.  Combo fields
  # can be nested with other combo fields.
  #
  Converters  = {
    integer:   lambda { |f|
      Integer(f.encode(ConverterEncoding)) rescue f
    },
    float:     lambda { |f|
      Float(f.encode(ConverterEncoding)) rescue f
    },
    numeric:   [:integer, :float],
    date:      lambda { |f|
      begin
        e = f.encode(ConverterEncoding)
        e.match?(DateMatcher) ? Date.parse(e) : f
      rescue  # encoding conversion or date parse errors
        f
      end
    },
    date_time: lambda { |f|
      begin
        e = f.encode(ConverterEncoding)
        e.match?(DateTimeMatcher) ? DateTime.parse(e) : f
      rescue  # encoding conversion or date parse errors
        f
      end
    },
    all:       [:date_time, :numeric],
  }

  #
  # This Hash holds the built-in header converters of CSV that can be accessed
  # by name.  You can select HeaderConverters with CSV.header_convert() or
  # through the +options+ Hash passed to CSV::new().
  #
  # <b><tt>:downcase</tt></b>::  Calls downcase() on the header String.
  # <b><tt>:symbol</tt></b>::    Leading/trailing spaces are dropped, string is
  #                              downcased, remaining spaces are replaced with
  #                              underscores, non-word characters are dropped,
  #                              and finally to_sym() is called.
  #
  # All built-in header converters transcode header data to UTF-8 before
  # attempting a conversion.  If your data cannot be transcoded to UTF-8 the
  # conversion will fail and the header will remain unchanged.
  #
  # This Hash is intentionally left unfrozen and users should feel free to add
  # values to it that can be accessed by all CSV objects.
  #
  # To add a combo field, the value should be an Array of names.  Combo fields
  # can be nested with other combo fields.
  #
  HeaderConverters = {
    downcase: lambda { |h| h.encode(ConverterEncoding).downcase },
    symbol:   lambda { |h|
      h.encode(ConverterEncoding).downcase.gsub(/[^\s\w]+/, "").strip.
                                           gsub(/\s+/, "_").to_sym
    }
  }

  #
  # The options used when no overrides are given by calling code.  They are:
  #
  # <b><tt>:col_sep</tt></b>::            <tt>","</tt>
  # <b><tt>:row_sep</tt></b>::            <tt>:auto</tt>
  # <b><tt>:quote_char</tt></b>::         <tt>'"'</tt>
  # <b><tt>:field_size_limit</tt></b>::   +nil+
  # <b><tt>:converters</tt></b>::         +nil+
  # <b><tt>:unconverted_fields</tt></b>:: +nil+
  # <b><tt>:headers</tt></b>::            +false+
  # <b><tt>:return_headers</tt></b>::     +false+
  # <b><tt>:header_converters</tt></b>::  +nil+
  # <b><tt>:skip_blanks</tt></b>::        +false+
  # <b><tt>:force_quotes</tt></b>::       +false+
  # <b><tt>:skip_lines</tt></b>::         +nil+
  # <b><tt>:liberal_parsing</tt></b>::    +false+
  # <b><tt>:quote_empty</tt></b>::        +true+
  #
  DEFAULT_OPTIONS = {
    col_sep:            ",",
    row_sep:            :auto,
    quote_char:         '"',
    field_size_limit:   nil,
    converters:         nil,
    unconverted_fields: nil,
    headers:            false,
    return_headers:     false,
    header_converters:  nil,
    skip_blanks:        false,
    force_quotes:       false,
    skip_lines:         nil,
    liberal_parsing:    false,
    quote_empty:        true,
  }.freeze

  #
  # This method will return a CSV instance, just like CSV::new(), but the
  # instance will be cached and returned for all future calls to this method for
  # the same +data+ object (tested by Object#object_id()) with the same
  # +options+.
  #
  # If a block is given, the instance is passed to the block and the return
  # value becomes the return value of the block.
  #
  def self.instance(data = $stdout, **options)
    # create a _signature_ for this method call, data object and options
    sig = [data.object_id] +
          options.values_at(*DEFAULT_OPTIONS.keys.sort_by { |sym| sym.to_s })

    # fetch or create the instance for this signature
    @@instances ||= Hash.new
    instance = (@@instances[sig] ||= new(data, options))

    if block_given?
      yield instance  # run block, if given, returning result
    else
      instance        # or return the instance
    end
  end

  #
  # :call-seq:
  #   filter( **options ) { |row| ... }
  #   filter( input, **options ) { |row| ... }
  #   filter( input, output, **options ) { |row| ... }
  #
  # This method is a convenience for building Unix-like filters for CSV data.
  # Each row is yielded to the provided block which can alter it as needed.
  # After the block returns, the row is appended to +output+ altered or not.
  #
  # The +input+ and +output+ arguments can be anything CSV::new() accepts
  # (generally String or IO objects).  If not given, they default to
  # <tt>ARGF</tt> and <tt>$stdout</tt>.
  #
  # The +options+ parameter is also filtered down to CSV::new() after some
  # clever key parsing.  Any key beginning with <tt>:in_</tt> or
  # <tt>:input_</tt> will have that leading identifier stripped and will only
  # be used in the +options+ Hash for the +input+ object.  Keys starting with
  # <tt>:out_</tt> or <tt>:output_</tt> affect only +output+.  All other keys
  # are assigned to both objects.
  #
  # The <tt>:output_row_sep</tt> +option+ defaults to
  # <tt>$INPUT_RECORD_SEPARATOR</tt> (<tt>$/</tt>).
  #
  def self.filter(input=nil, output=nil, **options)
    # parse options for input, output, or both
    in_options, out_options = Hash.new, {row_sep: $INPUT_RECORD_SEPARATOR}
    options.each do |key, value|
      case key.to_s
      when /\Ain(?:put)?_(.+)\Z/
        in_options[$1.to_sym] = value
      when /\Aout(?:put)?_(.+)\Z/
        out_options[$1.to_sym] = value
      else
        in_options[key]  = value
        out_options[key] = value
      end
    end
    # build input and output wrappers
    input  = new(input  || ARGF,    in_options)
    output = new(output || $stdout, out_options)

    # read, yield, write
    input.each do |row|
      yield row
      output << row
    end
  end

  #
  # This method is intended as the primary interface for reading CSV files.  You
  # pass a +path+ and any +options+ you wish to set for the read.  Each row of
  # file will be passed to the provided +block+ in turn.
  #
  # The +options+ parameter can be anything CSV::new() understands.  This method
  # also understands an additional <tt>:encoding</tt> parameter that you can use
  # to specify the Encoding of the data in the file to be read. You must provide
  # this unless your data is in Encoding::default_external().  CSV will use this
  # to determine how to parse the data.  You may provide a second Encoding to
  # have the data transcoded as it is read.  For example,
  # <tt>encoding: "UTF-32BE:UTF-8"</tt> would read UTF-32BE data from the file
  # but transcode it to UTF-8 before CSV parses it.
  #
  def self.foreach(path, **options, &block)
    return to_enum(__method__, path, options) unless block_given?
    open(path, options) do |csv|
      csv.each(&block)
    end
  end

  #
  # :call-seq:
  #   generate( str, **options ) { |csv| ... }
  #   generate( **options ) { |csv| ... }
  #
  # This method wraps a String you provide, or an empty default String, in a
  # CSV object which is passed to the provided block.  You can use the block to
  # append CSV rows to the String and when the block exits, the final String
  # will be returned.
  #
  # Note that a passed String *is* modified by this method.  Call dup() before
  # passing if you need a new String.
  #
  # The +options+ parameter can be anything CSV::new() understands.  This method
  # understands an additional <tt>:encoding</tt> parameter when not passed a
  # String to set the base Encoding for the output.  CSV needs this hint if you
  # plan to output non-ASCII compatible data.
  #
  def self.generate(str=nil, **options)
    # add a default empty String, if none was given
    if str
      str = StringIO.new(str)
      str.seek(0, IO::SEEK_END)
    else
      encoding = options[:encoding]
      str = +""
      str.force_encoding(encoding) if encoding
    end
    csv = new(str, options) # wrap
    yield csv         # yield for appending
    csv.string        # return final String
  end

  #
  # This method is a shortcut for converting a single row (Array) into a CSV
  # String.
  #
  # The +options+ parameter can be anything CSV::new() understands.  This method
  # understands an additional <tt>:encoding</tt> parameter to set the base
  # Encoding for the output.  This method will try to guess your Encoding from
  # the first non-+nil+ field in +row+, if possible, but you may need to use
  # this parameter as a backup plan.
  #
  # The <tt>:row_sep</tt> +option+ defaults to <tt>$INPUT_RECORD_SEPARATOR</tt>
  # (<tt>$/</tt>) when calling this method.
  #
  def self.generate_line(row, **options)
    options = {row_sep: $INPUT_RECORD_SEPARATOR}.merge(options)
    str = +""
    if options[:encoding]
      str.force_encoding(options[:encoding])
    elsif field = row.find {|f| f.is_a?(String)}
      str.force_encoding(field.encoding)
    end
    (new(str, options) << row).string
  end

  #
  # :call-seq:
  #   open( filename, mode = "rb", **options ) { |faster_csv| ... }
  #   open( filename, **options ) { |faster_csv| ... }
  #   open( filename, mode = "rb", **options )
  #   open( filename, **options )
  #
  # This method opens an IO object, and wraps that with CSV.  This is intended
  # as the primary interface for writing a CSV file.
  #
  # You must pass a +filename+ and may optionally add a +mode+ for Ruby's
  # open().  You may also pass an optional Hash containing any +options+
  # CSV::new() understands as the final argument.
  #
  # This method works like Ruby's open() call, in that it will pass a CSV object
  # to a provided block and close it when the block terminates, or it will
  # return the CSV object when no block is provided.  (*Note*: This is different
  # from the Ruby 1.8 CSV library which passed rows to the block.  Use
  # CSV::foreach() for that behavior.)
  #
  # You must provide a +mode+ with an embedded Encoding designator unless your
  # data is in Encoding::default_external().  CSV will check the Encoding of the
  # underlying IO object (set by the +mode+ you pass) to determine how to parse
  # the data.   You may provide a second Encoding to have the data transcoded as
  # it is read just as you can with a normal call to IO::open().  For example,
  # <tt>"rb:UTF-32BE:UTF-8"</tt> would read UTF-32BE data from the file but
  # transcode it to UTF-8 before CSV parses it.
  #
  # An opened CSV object will delegate to many IO methods for convenience.  You
  # may call:
  #
  # * binmode()
  # * binmode?()
  # * close()
  # * close_read()
  # * close_write()
  # * closed?()
  # * eof()
  # * eof?()
  # * external_encoding()
  # * fcntl()
  # * fileno()
  # * flock()
  # * flush()
  # * fsync()
  # * internal_encoding()
  # * ioctl()
  # * isatty()
  # * path()
  # * pid()
  # * pos()
  # * pos=()
  # * reopen()
  # * seek()
  # * stat()
  # * sync()
  # * sync=()
  # * tell()
  # * to_i()
  # * to_io()
  # * truncate()
  # * tty?()
  #
  def self.open(filename, mode="r", **options)
    # wrap a File opened with the remaining +args+ with no newline
    # decorator
    file_opts = {universal_newline: false}.merge(options)

    begin
      f = File.open(filename, mode, file_opts)
    rescue ArgumentError => e
      raise unless /needs binmode/.match?(e.message) and mode == "r"
      mode = "rb"
      file_opts = {encoding: Encoding.default_external}.merge(file_opts)
      retry
    end
    begin
      csv = new(f, options)
    rescue Exception
      f.close
      raise
    end

    # handle blocks like Ruby's open(), not like the CSV library
    if block_given?
      begin
        yield csv
      ensure
        csv.close
      end
    else
      csv
    end
  end

  #
  # :call-seq:
  #   parse( str, **options ) { |row| ... }
  #   parse( str, **options )
  #
  # This method can be used to easily parse CSV out of a String.  You may either
  # provide a +block+ which will be called with each row of the String in turn,
  # or just use the returned Array of Arrays (when no +block+ is given).
  #
  # You pass your +str+ to read from, and an optional +options+ containing
  # anything CSV::new() understands.
  #
  def self.parse(*args, &block)
    csv = new(*args)

    return csv.each(&block) if block_given?

    # slurp contents, if no block is given
    begin
      csv.read
    ensure
      csv.close
    end
  end

  #
  # This method is a shortcut for converting a single line of a CSV String into
  # an Array.  Note that if +line+ contains multiple rows, anything beyond the
  # first row is ignored.
  #
  # The +options+ parameter can be anything CSV::new() understands.
  #
  def self.parse_line(line, **options)
    new(line, options).shift
  end

  #
  # Use to slurp a CSV file into an Array of Arrays.  Pass the +path+ to the
  # file and any +options+ CSV::new() understands.  This method also understands
  # an additional <tt>:encoding</tt> parameter that you can use to specify the
  # Encoding of the data in the file to be read. You must provide this unless
  # your data is in Encoding::default_external().  CSV will use this to determine
  # how to parse the data.  You may provide a second Encoding to have the data
  # transcoded as it is read.  For example,
  # <tt>encoding: "UTF-32BE:UTF-8"</tt> would read UTF-32BE data from the file
  # but transcode it to UTF-8 before CSV parses it.
  #
  def self.read(path, *options)
    open(path, *options) { |csv| csv.read }
  end

  # Alias for CSV::read().
  def self.readlines(*args)
    read(*args)
  end

  #
  # A shortcut for:
  #
  #   CSV.read( path, { headers:           true,
  #                     converters:        :numeric,
  #                     header_converters: :symbol }.merge(options) )
  #
  def self.table(path, **options)
    read( path, { headers:           true,
                  converters:        :numeric,
                  header_converters: :symbol }.merge(options) )
  end

  #
  # This constructor will wrap either a String or IO object passed in +data+ for
  # reading and/or writing.  In addition to the CSV instance methods, several IO
  # methods are delegated.  (See CSV::open() for a complete list.)  If you pass
  # a String for +data+, you can later retrieve it (after writing to it, for
  # example) with CSV.string().
  #
  # Note that a wrapped String will be positioned at the beginning (for
  # reading).  If you want it at the end (for writing), use CSV::generate().
  # If you want any other positioning, pass a preset StringIO object instead.
  #
  # You may set any reading and/or writing preferences in the +options+ Hash.
  # Available options are:
  #
  # <b><tt>:col_sep</tt></b>::            The String placed between each field.
  #                                       This String will be transcoded into
  #                                       the data's Encoding before parsing.
  # <b><tt>:row_sep</tt></b>::            The String appended to the end of each
  #                                       row.  This can be set to the special
  #                                       <tt>:auto</tt> setting, which requests
  #                                       that CSV automatically discover this
  #                                       from the data.  Auto-discovery reads
  #                                       ahead in the data looking for the next
  #                                       <tt>"\r\n"</tt>, <tt>"\n"</tt>, or
  #                                       <tt>"\r"</tt> sequence.  A sequence
  #                                       will be selected even if it occurs in
  #                                       a quoted field, assuming that you
  #                                       would have the same line endings
  #                                       there.  If none of those sequences is
  #                                       found, +data+ is <tt>ARGF</tt>,
  #                                       <tt>STDIN</tt>, <tt>STDOUT</tt>, or
  #                                       <tt>STDERR</tt>, or the stream is only
  #                                       available for output, the default
  #                                       <tt>$INPUT_RECORD_SEPARATOR</tt>
  #                                       (<tt>$/</tt>) is used.  Obviously,
  #                                       discovery takes a little time.  Set
  #                                       manually if speed is important.  Also
  #                                       note that IO objects should be opened
  #                                       in binary mode on Windows if this
  #                                       feature will be used as the
  #                                       line-ending translation can cause
  #                                       problems with resetting the document
  #                                       position to where it was before the
  #                                       read ahead. This String will be
  #                                       transcoded into the data's Encoding
  #                                       before parsing.
  # <b><tt>:quote_char</tt></b>::         The character used to quote fields.
  #                                       This has to be a single character
  #                                       String.  This is useful for
  #                                       application that incorrectly use
  #                                       <tt>'</tt> as the quote character
  #                                       instead of the correct <tt>"</tt>.
  #                                       CSV will always consider a double
  #                                       sequence of this character to be an
  #                                       escaped quote. This String will be
  #                                       transcoded into the data's Encoding
  #                                       before parsing.
  # <b><tt>:field_size_limit</tt></b>::   This is a maximum size CSV will read
  #                                       ahead looking for the closing quote
  #                                       for a field.  (In truth, it reads to
  #                                       the first line ending beyond this
  #                                       size.)  If a quote cannot be found
  #                                       within the limit CSV will raise a
  #                                       MalformedCSVError, assuming the data
  #                                       is faulty.  You can use this limit to
  #                                       prevent what are effectively DoS
  #                                       attacks on the parser.  However, this
  #                                       limit can cause a legitimate parse to
  #                                       fail and thus is set to +nil+, or off,
  #                                       by default.
  # <b><tt>:converters</tt></b>::         An Array of names from the Converters
  #                                       Hash and/or lambdas that handle custom
  #                                       conversion.  A single converter
  #                                       doesn't have to be in an Array.  All
  #                                       built-in converters try to transcode
  #                                       fields to UTF-8 before converting.
  #                                       The conversion will fail if the data
  #                                       cannot be transcoded, leaving the
  #                                       field unchanged.
  # <b><tt>:unconverted_fields</tt></b>:: If set to +true+, an
  #                                       unconverted_fields() method will be
  #                                       added to all returned rows (Array or
  #                                       CSV::Row) that will return the fields
  #                                       as they were before conversion.  Note
  #                                       that <tt>:headers</tt> supplied by
  #                                       Array or String were not fields of the
  #                                       document and thus will have an empty
  #                                       Array attached.
  # <b><tt>:headers</tt></b>::            If set to <tt>:first_row</tt> or
  #                                       +true+, the initial row of the CSV
  #                                       file will be treated as a row of
  #                                       headers.  If set to an Array, the
  #                                       contents will be used as the headers.
  #                                       If set to a String, the String is run
  #                                       through a call of CSV::parse_line()
  #                                       with the same <tt>:col_sep</tt>,
  #                                       <tt>:row_sep</tt>, and
  #                                       <tt>:quote_char</tt> as this instance
  #                                       to produce an Array of headers.  This
  #                                       setting causes CSV#shift() to return
  #                                       rows as CSV::Row objects instead of
  #                                       Arrays and CSV#read() to return
  #                                       CSV::Table objects instead of an Array
  #                                       of Arrays.
  # <b><tt>:return_headers</tt></b>::     When +false+, header rows are silently
  #                                       swallowed.  If set to +true+, header
  #                                       rows are returned in a CSV::Row object
  #                                       with identical headers and
  #                                       fields (save that the fields do not go
  #                                       through the converters).
  # <b><tt>:write_headers</tt></b>::      When +true+ and <tt>:headers</tt> is
  #                                       set, a header row will be added to the
  #                                       output.
  # <b><tt>:header_converters</tt></b>::  Identical in functionality to
  #                                       <tt>:converters</tt> save that the
  #                                       conversions are only made to header
  #                                       rows.  All built-in converters try to
  #                                       transcode headers to UTF-8 before
  #                                       converting.  The conversion will fail
  #                                       if the data cannot be transcoded,
  #                                       leaving the header unchanged.
  # <b><tt>:skip_blanks</tt></b>::        When set to a +true+ value, CSV will
  #                                       skip over any empty rows. Note that
  #                                       this setting will not skip rows that
  #                                       contain column separators, even if
  #                                       the rows contain no actual data. If
  #                                       you want to skip rows that contain
  #                                       separators but no content, consider
  #                                       using <tt>:skip_lines</tt>, or
  #                                       inspecting fields.compact.empty? on
  #                                       each row.
  # <b><tt>:force_quotes</tt></b>::       When set to a +true+ value, CSV will
  #                                       quote all CSV fields it creates.
  # <b><tt>:skip_lines</tt></b>::         When set to an object responding to
  #                                       <tt>match</tt>, every line matching
  #                                       it is considered a comment and ignored
  #                                       during parsing. When set to a String,
  #                                       it is first converted to a Regexp.
  #                                       When set to +nil+ no line is considered
  #                                       a comment. If the passed object does
  #                                       not respond to <tt>match</tt>,
  #                                       <tt>ArgumentError</tt> is thrown.
  # <b><tt>:liberal_parsing</tt></b>::    When set to a +true+ value, CSV will
  #                                       attempt to parse input not conformant
  #                                       with RFC 4180, such as double quotes
  #                                       in unquoted fields.
  # <b><tt>:nil_value</tt></b>::          When set an object, any values of an
  #                                       empty field are replaced by the set
  #                                       object, not nil.
  # <b><tt>:empty_value</tt></b>::        When set an object, any values of a
  #                                       blank string field is replaced by
  #                                       the set object.
  # <b><tt>:quote_empty</tt></b>::        TODO
  #
  # See CSV::DEFAULT_OPTIONS for the default settings.
  #
  # Options cannot be overridden in the instance methods for performance reasons,
  # so be sure to set what you want here.
  #
  def initialize(data,
                 col_sep: ",",
                 row_sep: :auto,
                 quote_char: '"',
                 field_size_limit: nil,
                 converters: nil,
                 unconverted_fields: nil,
                 headers: false,
                 return_headers: false,
                 write_headers: nil,
                 header_converters: nil,
                 skip_blanks: false,
                 force_quotes: false,
                 skip_lines: nil,
                 liberal_parsing: false,
                 internal_encoding: nil,
                 external_encoding: nil,
                 encoding: nil,
                 nil_value: nil,
                 empty_value: "",
                 quote_empty: true)
    raise ArgumentError.new("Cannot parse nil as CSV") if data.nil?

    # create the IO object we will read from
    @io = data.is_a?(String) ? StringIO.new(data) : data
    @encoding = determine_encoding(encoding, internal_encoding)

    @base_fields_converter_options = {
      nil_value: nil_value,
      empty_value: empty_value,
    }
    @initial_converters = converters
    @initial_header_converters = header_converters

    @parser_options = {
      column_separator: col_sep,
      row_separator: row_sep,
      quote_character: quote_char,
      field_size_limit: field_size_limit,
      unconverted_fields: unconverted_fields,
      headers: headers,
      return_headers: return_headers,
      skip_blanks: skip_blanks,
      skip_lines: skip_lines,
      liberal_parsing: liberal_parsing,
      encoding: @encoding,
      nil_value: nil_value,
      empty_value: empty_value,
    }
    @parser = nil

    @writer_options = {
      encoding: @encoding,
      force_encoding: (not encoding.nil?),
      force_quotes: force_quotes,
      headers: headers,
      write_headers: write_headers,
      column_separator: col_sep,
      row_separator: row_sep,
      quote_character: quote_char,
      quote_empty: quote_empty,
    }

    @writer = nil
    writer if @writer_options[:write_headers]
  end

  #
  # The encoded <tt>:col_sep</tt> used in parsing and writing.  See CSV::new
  # for details.
  #
  def col_sep
    parser.column_separator
  end

  #
  # The encoded <tt>:row_sep</tt> used in parsing and writing.  See CSV::new
  # for details.
  #
  def row_sep
    parser.row_separator
  end

  #
  # The encoded <tt>:quote_char</tt> used in parsing and writing.  See CSV::new
  # for details.
  #
  def quote_char
    parser.quote_character
  end

  # The limit for field size, if any.  See CSV::new for details.
  def field_size_limit
    parser.field_size_limit
  end

  # The regex marking a line as a comment. See CSV::new for details
  def skip_lines
    parser.skip_lines
  end

  #
  # Returns the current list of converters in effect.  See CSV::new for details.
  # Built-in converters will be returned by name, while others will be returned
  # as is.
  #
  def converters
    fields_converter.map do |converter|
      name = Converters.rassoc(converter)
      name ? name.first : converter
    end
  end
  #
  # Returns +true+ if unconverted_fields() to parsed results.  See CSV::new
  # for details.
  #
  def unconverted_fields?
    parser.unconverted_fields?
  end

  #
  # Returns +nil+ if headers will not be used, +true+ if they will but have not
  # yet been read, or the actual headers after they have been read.  See
  # CSV::new for details.
  #
  def headers
    if @writer
      @writer.headers
    else
      parsed_headers = parser.headers
      return parsed_headers if parsed_headers
      raw_headers = @parser_options[:headers]
      raw_headers = nil if raw_headers == false
      raw_headers
    end
  end
  #
  # Returns +true+ if headers will be returned as a row of results.
  # See CSV::new for details.
  #
  def return_headers?
    parser.return_headers?
  end

  # Returns +true+ if headers are written in output. See CSV::new for details.
  def write_headers?
    @writer_options[:write_headers]
  end

  #
  # Returns the current list of converters in effect for headers.  See CSV::new
  # for details.  Built-in converters will be returned by name, while others
  # will be returned as is.
  #
  def header_converters
    header_fields_converter.map do |converter|
      name = HeaderConverters.rassoc(converter)
      name ? name.first : converter
    end
  end

  #
  # Returns +true+ blank lines are skipped by the parser. See CSV::new
  # for details.
  #
  def skip_blanks?
    parser.skip_blanks?
  end

  # Returns +true+ if all output fields are quoted. See CSV::new for details.
  def force_quotes?
    @writer_options[:force_quotes]
  end

  # Returns +true+ if illegal input is handled. See CSV::new for details.
  def liberal_parsing?
    parser.liberal_parsing?
  end

  #
  # The Encoding CSV is parsing or writing in.  This will be the Encoding you
  # receive parsed data in and/or the Encoding data will be written in.
  #
  attr_reader :encoding

  #
  # The line number of the last row read from this file. Fields with nested
  # line-end characters will not affect this count.
  #
  def lineno
    if @writer
      @writer.lineno
    else
      parser.lineno
    end
  end

  #
  # The last row read from this file.
  #
  def line
    parser.line
  end

  ### IO and StringIO Delegation ###

  extend Forwardable
  def_delegators :@io, :binmode, :binmode?, :close, :close_read, :close_write,
                       :closed?, :eof, :eof?, :external_encoding, :fcntl,
                       :fileno, :flock, :flush, :fsync, :internal_encoding,
                       :ioctl, :isatty, :path, :pid, :pos, :pos=, :reopen,
                       :seek, :stat, :string, :sync, :sync=, :tell, :to_i,
                       :to_io, :truncate, :tty?

  # Rewinds the underlying IO object and resets CSV's lineno() counter.
  def rewind
    @parser = nil
    @parser_enumerator = nil
    @writer.rewind if @writer
    @io.rewind
  end

  ### End Delegation ###

  #
  # The primary write method for wrapped Strings and IOs, +row+ (an Array or
  # CSV::Row) is converted to CSV and appended to the data source.  When a
  # CSV::Row is passed, only the row's fields() are appended to the output.
  #
  # The data source must be open for writing.
  #
  def <<(row)
    writer << row
    self
  end
  alias_method :add_row, :<<
  alias_method :puts,    :<<

  #
  # :call-seq:
  #   convert( name )
  #   convert { |field| ... }
  #   convert { |field, field_info| ... }
  #
  # You can use this method to install a CSV::Converters built-in, or provide a
  # block that handles a custom conversion.
  #
  # If you provide a block that takes one argument, it will be passed the field
  # and is expected to return the converted value or the field itself.  If your
  # block takes two arguments, it will also be passed a CSV::FieldInfo Struct,
  # containing details about the field.  Again, the block should return a
  # converted field or the field itself.
  #
  def convert(name = nil, &converter)
    fields_converter.add_converter(name, &converter)
  end

  #
  # :call-seq:
  #   header_convert( name )
  #   header_convert { |field| ... }
  #   header_convert { |field, field_info| ... }
  #
  # Identical to CSV#convert(), but for header rows.
  #
  # Note that this method must be called before header rows are read to have any
  # effect.
  #
  def header_convert(name = nil, &converter)
    header_fields_converter.add_converter(name, &converter)
  end

  include Enumerable

  #
  # Yields each row of the data source in turn.
  #
  # Support for Enumerable.
  #
  # The data source must be open for reading.
  #
  def each(&block)
    parser.parse(&block)
  end

  #
  # Slurps the remaining rows and returns an Array of Arrays.
  #
  # The data source must be open for reading.
  #
  def read
    rows = to_a
    if parser.use_headers?
      Table.new(rows, headers: parser.headers)
    else
      rows
    end
  end
  alias_method :readlines, :read

  # Returns +true+ if the next row read will be a header row.
  def header_row?
    parser.header_row?
  end

  #
  # The primary read method for wrapped Strings and IOs, a single row is pulled
  # from the data source, parsed and returned as an Array of fields (if header
  # rows are not used) or a CSV::Row (when header rows are used).
  #
  # The data source must be open for reading.
  #
  def shift
    @parser_enumerator ||= parser.parse
    begin
      @parser_enumerator.next
    rescue StopIteration
      nil
    end
  end
  alias_method :gets,     :shift
  alias_method :readline, :shift

  #
  # Returns a simplified description of the key CSV attributes in an
  # ASCII compatible String.
  #
  def inspect
    str = ["<#", self.class.to_s, " io_type:"]
    # show type of wrapped IO
    if    @io == $stdout then str << "$stdout"
    elsif @io == $stdin  then str << "$stdin"
    elsif @io == $stderr then str << "$stderr"
    else                      str << @io.class.to_s
    end
    # show IO.path(), if available
    if @io.respond_to?(:path) and (p = @io.path)
      str << " io_path:" << p.inspect
    end
    # show encoding
    str << " encoding:" << @encoding.name
    # show other attributes
    ["lineno", "col_sep", "row_sep", "quote_char"].each do |attr_name|
      if a = __send__(attr_name)
        str << " " << attr_name << ":" << a.inspect
      end
    end
    ["skip_blanks", "liberal_parsing"].each do |attr_name|
      if a = __send__("#{attr_name}?")
        str << " " << attr_name << ":" << a.inspect
      end
    end
    _headers = headers
    str << " headers:" << _headers.inspect if _headers
    str << ">"
    begin
      str.join('')
    rescue  # any encoding error
      str.map do |s|
        e = Encoding::Converter.asciicompat_encoding(s.encoding)
        e ? s.encode(e) : s.force_encoding("ASCII-8BIT")
      end.join('')
    end
  end

  private

  def determine_encoding(encoding, internal_encoding)
    # honor the IO encoding if we can, otherwise default to ASCII-8BIT
    io_encoding = raw_encoding
    return io_encoding if io_encoding

    return Encoding.find(internal_encoding) if internal_encoding

    if encoding
      encoding, = encoding.split(":", 2) if encoding.is_a?(String)
      return Encoding.find(encoding)
    end

    Encoding.default_internal || Encoding.default_external
  end

  def normalize_converters(converters)
    converters ||= []
    unless converters.is_a?(Array)
      converters = [converters]
    end
    converters.collect do |converter|
      case converter
      when Proc # custom code block
        [nil, converter]
      else # by name
        [converter, nil]
      end
    end
  end

  #
  # Processes +fields+ with <tt>@converters</tt>, or <tt>@header_converters</tt>
  # if +headers+ is passed as +true+, returning the converted field set.  Any
  # converter that changes the field into something other than a String halts
  # the pipeline of conversion for that field.  This is primarily an efficiency
  # shortcut.
  #
  def convert_fields(fields, headers = false)
    if headers
      header_fields_converter.convert(fields, nil, 0)
    else
      fields_converter.convert(fields, @headers, lineno)
    end
  end

  #
  # Returns the encoding of the internal IO object.
  #
  def raw_encoding
    if @io.respond_to? :internal_encoding
      @io.internal_encoding || @io.external_encoding
    elsif @io.respond_to? :encoding
      @io.encoding
    else
      nil
    end
  end

  def fields_converter
    @fields_converter ||= build_fields_converter
  end

  def build_fields_converter
    specific_options = {
      builtin_converters: Converters,
    }
    options = @base_fields_converter_options.merge(specific_options)
    fields_converter = FieldsConverter.new(options)
    normalize_converters(@initial_converters).each do |name, converter|
      fields_converter.add_converter(name, &converter)
    end
    fields_converter
  end

  def header_fields_converter
    @header_fields_converter ||= build_header_fields_converter
  end

  def build_header_fields_converter
    specific_options = {
      builtin_converters: HeaderConverters,
      accept_nil: true,
    }
    options = @base_fields_converter_options.merge(specific_options)
    fields_converter = FieldsConverter.new(options)
    normalize_converters(@initial_header_converters).each do |name, converter|
      fields_converter.add_converter(name, &converter)
    end
    fields_converter
  end

  def parser
    @parser ||= Parser.new(@io, parser_options)
  end

  def parser_options
    @parser_options.merge(fields_converter: fields_converter,
                          header_fields_converter: header_fields_converter)
  end

  def writer
    @writer ||= Writer.new(@io, writer_options)
  end

  def writer_options
    @writer_options.merge(header_fields_converter: header_fields_converter)
  end
end

# Passes +args+ to CSV::instance.
#
#   CSV("CSV,data").read
#     #=> [["CSV", "data"]]
#
# If a block is given, the instance is passed the block and the return value
# becomes the return value of the block.
#
#   CSV("CSV,data") { |c|
#     c.read.any? { |a| a.include?("data") }
#   } #=> true
#
#   CSV("CSV,data") { |c|
#     c.read.any? { |a| a.include?("zombies") }
#   } #=> false
#
def CSV(*args, &block)
  CSV.instance(*args, &block)
end

require_relative "csv/version"
require_relative "csv/core_ext/array"
require_relative "csv/core_ext/string"
