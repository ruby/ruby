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
# This version of the CSV library began its life as FasterCSV. FasterCSV was
# intended as a replacement to Ruby's then standard CSV library. It was
# designed to address concerns users of that library had and it had three
# primary goals:
#
# 1.  Be significantly faster than CSV while remaining a pure Ruby library.
# 2.  Use a smaller and easier to maintain code base. (FasterCSV eventually
#     grew larger, was also but considerably richer in features. The parsing
#     core remains quite small.)
# 3.  Improve on the CSV interface.
#
# Obviously, the last one is subjective. I did try to defer to the original
# interface whenever I didn't have a compelling reason to change it though, so
# hopefully this won't be too radically different.
#
# We must have met our goals because FasterCSV was renamed to CSV and replaced
# the original library as of Ruby 1.9. If you are migrating code from 1.8 or
# earlier, you may have to change your code to comply with the new interface.
#
# == What's the Different From the Old CSV?
#
# I'm sure I'll miss something, but I'll try to mention most of the major
# differences I am aware of, to help others quickly get up to speed:
#
# === CSV Parsing
#
# * This parser is m17n aware. See CSV for full details.
# * This library has a stricter parser and will throw MalformedCSVErrors on
#   problematic data.
# * This library has a less liberal idea of a line ending than CSV. What you
#   set as the <tt>:row_sep</tt> is law. It can auto-detect your line endings
#   though.
# * The old library returned empty lines as <tt>[nil]</tt>. This library calls
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
# * CSV no longer supports partial reads. It works line-by-line.
# * CSV no longer allows the instance methods to override the separators for
#   performance reasons. They must be set in the constructor.
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
# {the RFC}[http://www.ietf.org/rfc/rfc4180.txt]. I relax the rules in only one
# place and that is to make using this library easier. CSV will parse all valid
# CSV.
#
# What you don't want to do is to feed CSV invalid data. Because of the way the
# CSV format works, it's common for a parser to need to read until the end of
# the file to be sure a field is invalid. This consumes a lot of time and memory.
#
# Luckily, when working with invalid CSV, Ruby's built-in methods will almost
# always be superior in every way. For example, parsing non-quoted fields is as
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

# This class provides a complete interface to CSV files and data. It offers
# tools to enable you to read and write to and from Strings or IO objects, as
# needed.
#
# All examples here assume prior execution of:
#   require 'csv'
#
# The most generic interface of the library is:
#
#    csv = CSV.new(io, **options)
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
# == Delegated Methods
#
# For convenience, a CSV object will delegate to many methods in class IO.
# (A few have wrapper "guard code" in \CSV.) You may call:
# * IO#binmode
# * #binmode?
# * IO#close
# * IO#close_read
# * IO#close_write
# * IO#closed?
# * #eof
# * #eof?
# * IO#external_encoding
# * IO#fcntl
# * IO#fileno
# * #flock
# * IO#flush
# * IO#fsync
# * IO#internal_encoding
# * #ioctl
# * IO#isatty
# * #path
# * IO#pid
# * IO#pos
# * IO#pos=
# * IO#reopen
# * #rewind
# * IO#seek
# * #stat
# * IO#string
# * IO#sync
# * IO#sync=
# * IO#tell
# * #to_i
# * #to_io
# * IO#truncate
# * IO#tty?
#
# == Options
#
# The default values for options are:
#   DEFAULT_OPTIONS = {
#     # For both parsing and generating.
#     col_sep:            ",",
#     row_sep:            :auto,
#     quote_char:         '"',
#     # For parsing.
#     field_size_limit:   nil,
#     converters:         nil,
#     unconverted_fields: nil,
#     headers:            false,
#     return_headers:     false,
#     header_converters:  nil,
#     skip_blanks:        false,
#     skip_lines:         nil,
#     liberal_parsing:    false,
#     nil_value:          nil,
#     empty_value:        "",
#     # For generating.
#     write_headers:      nil,
#     quote_empty:        true,
#     force_quotes:       false,
#     write_converters:   nil,
#     write_nil_value:    nil,
#     write_empty_value:  "",
#     strip:              false,
#   }
#
# === Options for Parsing
#
# :include: ../doc/options/common/col_sep.rdoc
#
# :include: ../doc/options/common/row_sep.rdoc
#
# :include: ../doc/options/common/quote_char.rdoc
#
# :include: ../doc/options/parsing/field_size_limit.rdoc
#
# :include: ../doc/options/parsing/converters.rdoc
#
# :include: ../doc/options/parsing/unconverted_fields.rdoc
#
# :include: ../doc/options/parsing/headers.rdoc
#
# :include: ../doc/options/parsing/return_headers.rdoc
#
# :include: ../doc/options/parsing/header_converters.rdoc
#
# :include: ../doc/options/parsing/skip_blanks.rdoc
#
# :include: ../doc/options/parsing/skip_lines.rdoc
#
# :include: ../doc/options/parsing/strip.rdoc
#
# :include: ../doc/options/parsing/liberal_parsing.rdoc
#
# :include: ../doc/options/parsing/nil_value.rdoc
#
# :include: ../doc/options/parsing/empty_value.rdoc
#
# === Options for Generating
#
# :include: ../doc/options/common/col_sep.rdoc
#
# :include: ../doc/options/common/row_sep.rdoc
#
# :include: ../doc/options/common/quote_char.rdoc
#
# :include: ../doc/options/generating/write_headers.rdoc
#
# :include: ../doc/options/generating/force_quotes.rdoc
#
# :include: ../doc/options/generating/quote_empty.rdoc
#
# :include: ../doc/options/generating/write_converters.rdoc
#
# :include: ../doc/options/generating/write_nil_value.rdoc
#
# :include: ../doc/options/generating/write_empty_value.rdoc
#
# == CSV with headers
#
# CSV allows to specify column names of CSV file, whether they are in data, or
# provided separately. If headers are specified, reading methods return an instance
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
#   data = CSV.parse('Bob,Engineering,1000', headers: %i[name department salary])
#   data.first      #=> #<CSV::Row name:"Bob" department:"Engineering" salary:"1000">
#
# == \CSV \Converters
#
# By default, each field parsed by \CSV is formed into a \String.
# You can use a _converter_ to convert certain fields into other Ruby objects.
#
# When you specify a converter for parsing,
# each parsed field is passed to the converter;
# its return value becomes the new value for the field.
# A converter might, for example, convert an integer embedded in a \String
# into a true \Integer.
# (In fact, that's what built-in field converter +:integer+ does.)
#
# There are additional built-in \converters, and custom \converters are also supported.
#
# All \converters try to transcode fields to UTF-8 before converting.
# The conversion will fail if the data cannot be transcoded, leaving the field unchanged.
#
# === Field \Converters
#
# There are three ways to use field \converters;
# these examples use built-in field converter +:integer+,
# which converts each parsed integer string to a true \Integer.
#
# Option +converters+ with a singleton parsing method:
#   ary = CSV.parse_line('0,1,2', converters: :integer)
#   ary # => [0, 1, 2]
#
# Option +converters+ with a new \CSV instance:
#   csv = CSV.new('0,1,2', converters: :integer)
#   # Field converters in effect:
#   csv.converters # => [:integer]
#   csv.shift # => [0, 1, 2]
#
# Method #convert adds a field converter to a \CSV instance:
#   csv = CSV.new('0,1,2')
#   # Add a converter.
#   csv.convert(:integer)
#   csv.converters # => [:integer]
#   csv.shift # => [0, 1, 2]
#
# ---
#
# The built-in field \converters are in \Hash CSV::Converters.
# The \Symbol keys there are the names of the \converters:
#
#   CSV::Converters.keys # => [:integer, :float, :numeric, :date, :date_time, :all]
#
# Converter +:integer+ converts each field that +Integer()+ accepts:
#   data = '0,1,2,x'
#   # Without the converter
#   csv = CSV.parse_line(data)
#   csv # => ["0", "1", "2", "x"]
#   # With the converter
#   csv = CSV.parse_line(data, converters: :integer)
#   csv # => [0, 1, 2, "x"]
#
# Converter +:float+ converts each field that +Float()+ accepts:
#   data = '1.0,3.14159,x'
#   # Without the converter
#   csv = CSV.parse_line(data)
#   csv # => ["1.0", "3.14159", "x"]
#   # With the converter
#   csv = CSV.parse_line(data, converters: :float)
#   csv # => [1.0, 3.14159, "x"]
#
# Converter +:numeric+ converts with both +:integer+ and +:float+..
#
# Converter +:date+ converts each field that +Date::parse()+ accepts:
#   data = '2001-02-03,x'
#   # Without the converter
#   csv = CSV.parse_line(data)
#   csv # => ["2001-02-03", "x"]
#   # With the converter
#   csv = CSV.parse_line(data, converters: :date)
#   csv # => [#<Date: 2001-02-03 ((2451944j,0s,0n),+0s,2299161j)>, "x"]
#
# Converter +:date_time+ converts each field that +DateTime::parse() accepts:
#   data = '2020-05-07T14:59:00-05:00,x'
#   # Without the converter
#   csv = CSV.parse_line(data)
#   csv # => ["2020-05-07T14:59:00-05:00", "x"]
#   # With the converter
#   csv = CSV.parse_line(data, converters: :date_time)
#   csv # => [#<DateTime: 2020-05-07T14:59:00-05:00 ((2458977j,71940s,0n),-18000s,2299161j)>, "x"]
#
# Converter +:numeric+ converts with both +:date_time+ and +:numeric+..
#
# As seen above, method #convert adds \converters to a \CSV instance,
# and method #converters returns an \Array of the \converters in effect:
#   csv = CSV.new('0,1,2')
#   csv.converters # => []
#   csv.convert(:integer)
#   csv.converters # => [:integer]
#   csv.convert(:date)
#   csv.converters # => [:integer, :date]
#
# You can add a custom field converter to \Hash CSV::Converters:
#   strip_converter = proc {|field| field.strip}
#   CSV::Converters[:strip] = strip_converter
#   CSV::Converters.keys # => [:integer, :float, :numeric, :date, :date_time, :all, :strip]
#
# Then use it to convert fields:
#   str = ' foo , 0 '
#   ary = CSV.parse_line(str, converters: :strip)
#   ary # => ["foo", "0"]
#
# See {Custom Converters}[#class-CSV-label-Custom+Converters].
#
# === Header \Converters
#
# Header converters operate only on headers (and not on other rows).
#
# There are three ways to use header \converters;
# these examples use built-in header converter +:dowhcase+,
# which downcases each parsed header.
#
# Option +header_converters+ with a singleton parsing method:
#   str = "Name,Count\nFoo,0\n,Bar,1\nBaz,2"
#   tbl = CSV.parse(str, headers: true, header_converters: :downcase)
#   tbl.class # => CSV::Table
#   tbl.headers # => ["name", "count"]
#
# Option +header_converters+ with a new \CSV instance:
#   csv = CSV.new(str, header_converters: :downcase)
#   # Header converters in effect:
#   csv.header_converters # => [:downcase]
#   tbl = CSV.parse(str, headers: true)
#   tbl.headers # => ["Name", "Count"]
#
# Method #header_convert adds a header converter to a \CSV instance:
#   csv = CSV.new(str)
#   # Add a header converter.
#   csv.header_convert(:downcase)
#   csv.header_converters # => [:downcase]
#   tbl = CSV.parse(str, headers: true)
#   tbl.headers # => ["Name", "Count"]
#
# ---
#
# The built-in header \converters are in \Hash CSV::Converters.
# The \Symbol keys there are the names of the \converters:
#
#   CSV::HeaderConverters.keys # => [:downcase, :symbol]
#
# Converter +:downcase+ converts each header by downcasing it:
#   str = "Name,Count\nFoo,0\n,Bar,1\nBaz,2"
#   tbl = CSV.parse(str, headers: true, header_converters: :downcase)
#   tbl.class # => CSV::Table
#   tbl.headers # => ["name", "count"]
#
# Converter +:symbol+ by making it into a \Symbol:
#   str = "Name,Count\nFoo,0\n,Bar,1\nBaz,2"
#   tbl = CSV.parse(str, headers: true, header_converters: :symbol)
#   tbl.headers # => [:name, :count]
# Details:
# - Strips leading and trailing whitespace.
# - Downcases the header.
# - Replaces embedded spaces with underscores.
# - Removes non-word characters.
# - Makes the string into a \Symbol.
#
# You can add a custom header converter to \Hash CSV::HeaderConverters:
#   strip_converter = proc {|field| field.strip}
#   CSV::HeaderConverters[:strip] = strip_converter
#   CSV::HeaderConverters.keys # => [:downcase, :symbol, :strip]
#
# Then use it to convert headers:
#   str = " Name , Value \nfoo,0\nbar,1\nbaz,2"
#   tbl = CSV.parse(str, headers: true, header_converters: :strip)
#   tbl.headers # => ["Name", "Value"]
#
# See {Custom Converters}[#class-CSV-label-Custom+Converters].
#
# === Custom \Converters
#
# You can define custom \converters.
#
# The \converter is a \Proc that is called with two arguments,
# \String +field+ and CSV::FieldInfo +field_info+;
# it returns a \String that will become the field value:
#   converter = proc {|field, field_info| <some_string> }
#
# To illustrate:
#   converter = proc {|field, field_info| p [field, field_info]; field}
#   ary = CSV.parse_line('foo,0', converters: converter)
#
# Produces:
#   ["foo", #<struct CSV::FieldInfo index=0, line=1, header=nil>]
#   ["0", #<struct CSV::FieldInfo index=1, line=1, header=nil>]
#
# In each of the output lines:
# - The first \Array element is the passed \String field.
# - The second is a \FieldInfo structure containing information about the field:
#   - The 0-based column index.
#   - The 1-based line number.
#   - The header for the column, if available.
#
# If the \converter does not need +field_info+, it can be omitted:
#   converter = proc {|field| ... }
#
# == CSV and Character Encodings (M17n or Multilingualization)
#
# This new CSV parser is m17n savvy.  The parser works in the Encoding of the IO
# or String object being read from or written to. Your data is never transcoded
# (unless you ask Ruby to transcode it for you) and will literally be parsed in
# the Encoding it is in. Thus CSV will return Arrays or Rows of Strings in the
# Encoding of your data. This is accomplished by transcoding the parser itself
# into your Encoding.
#
# Some transcoding must take place, of course, to accomplish this multiencoding
# support. For example, <tt>:col_sep</tt>, <tt>:row_sep</tt>, and
# <tt>:quote_char</tt> must be transcoded to match your data.  Hopefully this
# makes the entire process feel transparent, since CSV's defaults should just
# magically work for your data. However, you can set these values manually in
# the target Encoding to avoid the translation.
#
# It's also important to note that while all of CSV's core parser is now
# Encoding agnostic, some features are not. For example, the built-in
# converters will try to transcode data to UTF-8 before making conversions.
# Again, you can provide custom converters that are aware of your Encodings to
# avoid this translation. It's just too hard for me to support native
# conversions in all of Ruby's Encodings.
#
# Anyway, the practical side of this is simple: make sure IO and String objects
# passed into CSV have the proper Encoding set and everything should just work.
# CSV methods that allow you to open IO objects (CSV::foreach(), CSV::open(),
# CSV::read(), and CSV::readlines()) do allow you to specify the Encoding.
#
# One minor exception comes when generating CSV into a String with an Encoding
# that is not ASCII compatible. There's no existing data for CSV to use to
# prepare itself and thus you will probably need to manually specify the desired
# Encoding for most of those cases. It will try to guess using the fields in a
# row of output though, when using CSV::generate_line() or Array#to_csv().
#
# I try to point out any other Encoding issues in the documentation of methods
# as they come up.
#
# This has been tested to the best of my ability with all non-"dummy" Encodings
# Ruby ships with. However, it is brave new code and may have some bugs.
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
  # by name. You can select HeaderConverters with CSV.header_convert() or
  # through the +options+ Hash passed to CSV::new().
  #
  # <b><tt>:downcase</tt></b>::  Calls downcase() on the header String.
  # <b><tt>:symbol</tt></b>::    Leading/trailing spaces are dropped, string is
  #                              downcased, remaining spaces are replaced with
  #                              underscores, non-word characters are dropped,
  #                              and finally to_sym() is called.
  #
  # All built-in header converters transcode header data to UTF-8 before
  # attempting a conversion. If your data cannot be transcoded to UTF-8 the
  # conversion will fail and the header will remain unchanged.
  #
  # This Hash is intentionally left unfrozen and users should feel free to add
  # values to it that can be accessed by all CSV objects.
  #
  # To add a combo field, the value should be an Array of names. Combo fields
  # can be nested with other combo fields.
  #
  HeaderConverters = {
    downcase: lambda { |h| h.encode(ConverterEncoding).downcase },
    symbol:   lambda { |h|
      h.encode(ConverterEncoding).downcase.gsub(/[^\s\w]+/, "").strip.
                                           gsub(/\s+/, "_").to_sym
    }
  }
  # Default values for method options.
  DEFAULT_OPTIONS = {
    # For both parsing and generating.
    col_sep:            ",",
    row_sep:            :auto,
    quote_char:         '"',
    # For parsing.
    field_size_limit:   nil,
    converters:         nil,
    unconverted_fields: nil,
    headers:            false,
    return_headers:     false,
    header_converters:  nil,
    skip_blanks:        false,
    skip_lines:         nil,
    liberal_parsing:    false,
    nil_value:          nil,
    empty_value:        "",
    # For generating.
    write_headers:      nil,
    quote_empty:        true,
    force_quotes:       false,
    write_converters:   nil,
    write_nil_value:    nil,
    write_empty_value:  "",
    strip:              false,
  }.freeze

  class << self
    # :call-seq:
    #   instance(string, **options)
    #   instance(io = $stdout, **options)
    #   instance(string, **options) {|csv| ... }
    #   instance(io = $stdout, **options) {|csv| ... }
    #
    # Creates or retrieves cached \CSV objects.
    # For arguments and options, see CSV.new.
    #
    # ---
    #
    # With no block given, returns a \CSV object.
    #
    # The first call to +instance+ creates and caches a \CSV object:
    #   s0 = 's0'
    #   csv0 = CSV.instance(s0)
    #   csv0.class # => CSV
    #
    # Subsequent calls to +instance+ with that _same_ +string+ or +io+
    # retrieve that same cached object:
    #   csv1 = CSV.instance(s0)
    #   csv1.class # => CSV
    #   csv1.equal?(csv0) # => true # Same CSV object
    #
    # A subsequent call to +instance+ with a _different_ +string+ or +io+
    # creates and caches a _different_ \CSV object.
    #   s1 = 's1'
    #   csv2 = CSV.instance(s1)
    #   csv2.equal?(csv0) # => false # Different CSV object
    #
    # All the cached objects remains available:
    #   csv3 = CSV.instance(s0)
    #   csv3.equal?(csv0) # true # Same CSV object
    #   csv4 = CSV.instance(s1)
    #   csv4.equal?(csv2) # true # Same CSV object
    #
    # ---
    #
    # When a block is given, calls the block with the created or retrieved
    # \CSV object; returns the block's return value:
    #   CSV.instance(s0) {|csv| :foo } # => :foo
    def instance(data = $stdout, **options)
      # create a _signature_ for this method call, data object and options
      sig = [data.object_id] +
            options.values_at(*DEFAULT_OPTIONS.keys.sort_by { |sym| sym.to_s })

      # fetch or create the instance for this signature
      @@instances ||= Hash.new
      instance = (@@instances[sig] ||= new(data, **options))

      if block_given?
        yield instance  # run block, if given, returning result
      else
        instance        # or return the instance
      end
    end

    # :call-seq:
    #   filter(**options) {|row| ... }
    #   filter(in_string, **options) {|row| ... }
    #   filter(in_io, **options) {|row| ... }
    #   filter(in_string, out_string, **options) {|row| ... }
    #   filter(in_string, out_io, **options) {|row| ... }
    #   filter(in_io, out_string, **options) {|row| ... }
    #   filter(in_io, out_io, **options) {|row| ... }
    #
    # Reads \CSV input and writes \CSV output.
    #
    # For each input row:
    # - Forms the data into:
    #   - A CSV::Row object, if headers are in use.
    #   - An \Array of Arrays, otherwise.
    # - Calls the block with that object.
    # - Appends the block's return value to the output.
    #
    # Arguments:
    # * \CSV source:
    #   * Argument +in_string+, if given, should be a \String object;
    #     it will be put into a new StringIO object positioned at the beginning.
    #   * Argument +in_io+, if given, should be an IO object that is
    #     open for reading; on return, the IO object will be closed.
    #   * If neither  +in_string+ nor +in_io+ is given,
    #     the input stream defaults to {ARGF}[https://ruby-doc.org/core/ARGF.html].
    # * \CSV output:
    #   * Argument +out_string+, if given, should be a \String object;
    #     it will be put into a new StringIO object positioned at the beginning.
    #   * Argument +out_io+, if given, should be an IO object that is
    #     ppen for writing; on return, the IO object will be closed.
    #   * If neither +out_string+ nor +out_io+ is given,
    #     the output stream defaults to <tt>$stdout</tt>.
    # * Argument +options+ should be keyword arguments.
    #   - Each argument name that is prefixed with +in_+ or +input_+
    #     is stripped of its prefix and is treated as an option
    #     for parsing the input.
    #     Option +input_row_sep+ defaults to <tt>$INPUT_RECORD_SEPARATOR</tt>.
    #   - Each argument name that is prefixed with +out_+ or +output_+
    #     is stripped of its prefix and is treated as an option
    #     for generating the output.
    #     Option +output_row_sep+ defaults to <tt>$INPUT_RECORD_SEPARATOR</tt>.
    #   - Each argument not prefixed as above is treated as an option
    #     both for parsing the input and for generating the output.
    #   - See {Options for Parsing}[#class-CSV-label-Options+for+Parsing]
    #     and {Options for Generating}[#class-CSV-label-Options+for+Generating].
    #
    # Example:
    #   in_string = "foo,0\nbar,1\nbaz,2\n"
    #   out_string = ''
    #   CSV.filter(in_string, out_string) do |row|
    #     row[0] = row[0].upcase
    #     row[1] *= 4
    #   end
    #   out_string # => "FOO,0000\nBAR,1111\nBAZ,2222\n"
    def filter(input=nil, output=nil, **options)
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
      input  = new(input  || ARGF,    **in_options)
      output = new(output || $stdout, **out_options)

      # read, yield, write
      input.each do |row|
        yield row
        output << row
      end
    end

    #
    # :call-seq:
    #   foreach(path, mode='r', **options) {|row| ... )
    #   foreach(io, mode='r', **options {|row| ... )
    #   foreach(path, mode='r', headers: ..., **options) {|row| ... )
    #   foreach(io, mode='r', headers: ..., **options {|row| ... )
    #   foreach(path, mode='r', **options) -> new_enumerator
    #   foreach(io, mode='r', **options -> new_enumerator
    #
    # Calls the block with each row read from source +path+ or +io+.
    #
    # * Argument +path+, if given, must be the path to a file.
    # :include: ../doc/arguments/io.rdoc
    # * Argument +mode+, if given, must be a \File mode
    #   See {Open Mode}[IO.html#method-c-new-label-Open+Mode].
    # * Arguments <tt>**options</tt> must be keyword options.
    #   See {Options for Parsing}[#class-CSV-label-Options+for+Parsing].
    # * This method optionally accepts an additional <tt>:encoding</tt> option
    #   that you can use to specify the Encoding of the data read from +path+ or +io+.
    #   You must provide this unless your data is in the encoding
    #   given by <tt>Encoding::default_external</tt>.
    #   Parsing will use this to determine how to parse the data.
    #   You may provide a second Encoding to
    #   have the data transcoded as it is read. For example,
    #     encoding: 'UTF-32BE:UTF-8'
    #   would read +UTF-32BE+ data from the file
    #   but transcode it to +UTF-8+ before parsing.
    #
    # ====== Without Option +headers+
    #
    # Without option +headers+, returns each row as an \Array object.
    #
    # These examples assume prior execution of:
    #   string = "foo,0\nbar,1\nbaz,2\n"
    #   path = 't.csv'
    #   File.write(path, string)
    #
    # Read rows from a file at +path+:
    #   CSV.foreach(path) {|row| p row }
    # Output:
    #   ["foo", "0"]
    #   ["bar", "1"]
    #   ["baz", "2"]
    #
    # Read rows from an \IO object:
    #   File.open(path) do |file|
    #     CSV.foreach(file) {|row| p row }
    #   end
    #
    # Output:
    #   ["foo", "0"]
    #   ["bar", "1"]
    #   ["baz", "2"]
    #
    # Returns a new \Enumerator if no block given:
    #   CSV.foreach(path) # => #<Enumerator: CSV:foreach("t.csv", "r")>
    #   CSV.foreach(File.open(path)) # => #<Enumerator: CSV:foreach(#<File:t.csv>, "r")>
    #
    # Issues a warning if an encoding is unsupported:
    #   CSV.foreach(File.open(path), encoding: 'foo:bar') {|row| }
    # Output:
    #   warning: Unsupported encoding foo ignored
    #   warning: Unsupported encoding bar ignored
    #
    # ====== With Option +headers+
    #
    # With {option +headers+}[#class-CSV-label-Option+headers],
    # returns each row as a CSV::Row object.
    #
    # These examples assume prior execution of:
    #   string = "Name,Count\nfoo,0\nbar,1\nbaz,2\n"
    #   path = 't.csv'
    #   File.write(path, string)
    #
    # Read rows from a file at +path+:
    #   CSV.foreach(path, headers: true) {|row| p row }
    #
    # Output:
    #   #<CSV::Row "Name":"foo" "Count":"0">
    #   #<CSV::Row "Name":"bar" "Count":"1">
    #   #<CSV::Row "Name":"baz" "Count":"2">
    #
    # Read rows from an \IO object:
    #   File.open(path) do |file|
    #     CSV.foreach(file, headers: true) {|row| p row }
    #   end
    #
    # Output:
    #   #<CSV::Row "Name":"foo" "Count":"0">
    #   #<CSV::Row "Name":"bar" "Count":"1">
    #   #<CSV::Row "Name":"baz" "Count":"2">
    #
    # ---
    #
    # Raises an exception if +path+ is a \String, but not the path to a readable file:
    #   # Raises Errno::ENOENT (No such file or directory @ rb_sysopen - nosuch.csv):
    #   CSV.foreach('nosuch.csv') {|row| }
    #
    # Raises an exception if +io+ is an \IO object, but not open for reading:
    #   io = File.open(path, 'w') {|row| }
    #   # Raises TypeError (no implicit conversion of nil into String):
    #   CSV.foreach(io) {|row| }
    #
    # Raises an exception if +mode+ is invalid:
    #   # Raises ArgumentError (invalid access mode nosuch):
    #   CSV.foreach(path, 'nosuch') {|row| }
    #
    def foreach(path, mode="r", **options, &block)
      return to_enum(__method__, path, mode, **options) unless block_given?
      open(path, mode, **options) do |csv|
        csv.each(&block)
      end
    end

    #
    # :call-seq:
    #   generate(csv_string, **options) {|csv| ... }
    #   generate(**options) {|csv| ... }
    #
    # * Argument +csv_string+, if given, must be a \String object;
    #   defaults to a new empty \String.
    # * Arguments +options+, if given, should be generating options.
    #   See {Options for Generating}[#class-CSV-label-Options+for+Generating].
    #
    # ---
    #
    # Creates a new \CSV object via <tt>CSV.new(csv_string, **options)</tt>;
    # calls the block with the \CSV object, which the block may modify;
    # returns the \String generated from the \CSV object.
    #
    # Note that a passed \String *is* modified by this method.
    # Pass <tt>csv_string</tt>.dup if the \String must be preserved.
    #
    # This method has one additional option: <tt>:encoding</tt>,
    # which sets the base Encoding for the output if no no +str+ is specified.
    # CSV needs this hint if you plan to output non-ASCII compatible data.
    #
    # ---
    #
    # Add lines:
    #   input_string = "foo,0\nbar,1\nbaz,2\n"
    #   output_string = CSV.generate(input_string) do |csv|
    #     csv << ['bat', 3]
    #     csv << ['bam', 4]
    #   end
    #   output_string # => "foo,0\nbar,1\nbaz,2\nbat,3\nbam,4\n"
    #   input_string # => "foo,0\nbar,1\nbaz,2\nbat,3\nbam,4\n"
    #   output_string.equal?(input_string) # => true # Same string, modified
    #
    # Add lines into new string, preserving old string:
    #   input_string = "foo,0\nbar,1\nbaz,2\n"
    #   output_string = CSV.generate(input_string.dup) do |csv|
    #     csv << ['bat', 3]
    #     csv << ['bam', 4]
    #   end
    #   output_string # => "foo,0\nbar,1\nbaz,2\nbat,3\nbam,4\n"
    #   input_string # => "foo,0\nbar,1\nbaz,2\n"
    #   output_string.equal?(input_string) # => false # Different strings
    #
    # Create lines from nothing:
    #   output_string = CSV.generate do |csv|
    #     csv << ['foo', 0]
    #     csv << ['bar', 1]
    #     csv << ['baz', 2]
    #   end
    #   output_string # => "foo,0\nbar,1\nbaz,2\n"
    #
    # ---
    #
    # Raises an exception if +csv_string+ is not a \String object:
    #   # Raises TypeError (no implicit conversion of Integer into String)
    #   CSV.generate(0)
    #
    def generate(str=nil, **options)
      encoding = options[:encoding]
      # add a default empty String, if none was given
      if str
        str = StringIO.new(str)
        str.seek(0, IO::SEEK_END)
        str.set_encoding(encoding) if encoding
      else
        str = +""
        str.force_encoding(encoding) if encoding
      end
      csv = new(str, **options) # wrap
      yield csv         # yield for appending
      csv.string        # return final String
    end

    # :call-seq:
    #   CSV.generate_line(ary)
    #   CSV.generate_line(ary, **options)
    #
    # Returns the \String created by generating \CSV from +ary+
    # using the specified +options+.
    #
    # Argument +ary+ must be an \Array.
    #
    # Special options:
    # * Option <tt>:row_sep</tt> defaults to <tt>$INPUT_RECORD_SEPARATOR</tt>
    #   (<tt>$/</tt>).:
    #     $INPUT_RECORD_SEPARATOR # => "\n"
    # * This method accepts an additional option, <tt>:encoding</tt>, which sets the base
    #   Encoding for the output. This method will try to guess your Encoding from
    #   the first non-+nil+ field in +row+, if possible, but you may need to use
    #   this parameter as a backup plan.
    #
    # For other +options+,
    # see {Options for Generating}[#class-CSV-label-Options+for+Generating].
    #
    # ---
    #
    # Returns the \String generated from an \Array:
    #   CSV.generate_line(['foo', '0']) # => "foo,0\n"
    #
    # ---
    #
    # Raises an exception if +ary+ is not an \Array:
    #   # Raises NoMethodError (undefined method `find' for :foo:Symbol)
    #   CSV.generate_line(:foo)
    #
    def generate_line(row, **options)
      options = {row_sep: $INPUT_RECORD_SEPARATOR}.merge(options)
      str = +""
      if options[:encoding]
        str.force_encoding(options[:encoding])
      elsif field = row.find {|f| f.is_a?(String)}
        str.force_encoding(field.encoding)
      end
      (new(str, **options) << row).string
    end

    #
    # :call-seq:
    #   open(file_path, mode = "rb", **options ) -> new_csv
    #   open(io, mode = "rb", **options ) -> new_csv
    #   open(file_path, mode = "rb", **options ) { |csv| ... } -> object
    #   open(io, mode = "rb", **options ) { |csv| ... } -> object
    #
    # possible options elements:
    #   hash form:
    #     :invalid => nil      # raise error on invalid byte sequence (default)
    #     :invalid => :replace # replace invalid byte sequence
    #     :undef => :replace   # replace undefined conversion
    #     :replace => string   # replacement string ("?" or "\uFFFD" if not specified)
    #
    # * Argument +path+, if given, must be the path to a file.
    # :include: ../doc/arguments/io.rdoc
    # * Argument +mode+, if given, must be a \File mode
    #   See {Open Mode}[IO.html#method-c-new-label-Open+Mode].
    # * Arguments <tt>**options</tt> must be keyword options.
    #   See {Options for Generating}[#class-CSV-label-Options+for+Generating].
    # * This method optionally accepts an additional <tt>:encoding</tt> option
    #   that you can use to specify the Encoding of the data read from +path+ or +io+.
    #   You must provide this unless your data is in the encoding
    #   given by <tt>Encoding::default_external</tt>.
    #   Parsing will use this to determine how to parse the data.
    #   You may provide a second Encoding to
    #   have the data transcoded as it is read. For example,
    #     encoding: 'UTF-32BE:UTF-8'
    #   would read +UTF-32BE+ data from the file
    #   but transcode it to +UTF-8+ before parsing.
    #
    # ---
    #
    # These examples assume prior execution of:
    #   string = "foo,0\nbar,1\nbaz,2\n"
    #   path = 't.csv'
    #   File.write(path, string)
    #
    # ---
    #
    # With no block given, returns a new \CSV object.
    #
    # Create a \CSV object using a file path:
    #   csv = CSV.open(path)
    #   csv # => #<CSV io_type:File io_path:"t.csv" encoding:UTF-8 lineno:0 col_sep:"," row_sep:"\r\n" quote_char:"\"">
    #
    # Create a \CSV object using an open \File:
    #   csv = CSV.open(File.open(path))
    #   csv # => #<CSV io_type:File io_path:"t.csv" encoding:UTF-8 lineno:0 col_sep:"," row_sep:"\r\n" quote_char:"\"">
    #
    # ---
    #
    # With a block given, calls the block with the created \CSV object;
    # returns the block's return value:
    #
    # Using a file path:
    #   csv = CSV.open(path) {|csv| p csv}
    #   csv # => #<CSV io_type:File io_path:"t.csv" encoding:UTF-8 lineno:0 col_sep:"," row_sep:"\r\n" quote_char:"\"">
    # Output:
    #   #<CSV io_type:File io_path:"t.csv" encoding:UTF-8 lineno:0 col_sep:"," row_sep:"\r\n" quote_char:"\"">
    #
    # Using an open \File:
    #   csv = CSV.open(File.open(path)) {|csv| p csv}
    #   csv # => #<CSV io_type:File io_path:"t.csv" encoding:UTF-8 lineno:0 col_sep:"," row_sep:"\r\n" quote_char:"\"">
    # Output:
    #   #<CSV io_type:File io_path:"t.csv" encoding:UTF-8 lineno:0 col_sep:"," row_sep:"\r\n" quote_char:"\"">
    #
    # ---
    #
    # Raises an exception if the argument is not a \String object or \IO object:
    #   # Raises TypeError (no implicit conversion of Symbol into String)
    #   CSV.open(:foo)
    def open(filename, mode="r", **options)
      # wrap a File opened with the remaining +args+ with no newline
      # decorator
      file_opts = {universal_newline: false}.merge(options)
      options.delete(:invalid)
      options.delete(:undef)
      options.delete(:replace)

      begin
        f = File.open(filename, mode, **file_opts)
      rescue ArgumentError => e
        raise unless /needs binmode/.match?(e.message) and mode == "r"
        mode = "rb"
        file_opts = {encoding: Encoding.default_external}.merge(file_opts)
        retry
      end
      begin
        csv = new(f, **options)
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
    #   parse(string) -> array_of_arrays
    #   parse(io) -> array_of_arrays
    #   parse(string, headers: ..., **options) -> csv_table
    #   parse(io, headers: ..., **options) -> csv_table
    #   parse(string, **options) {|row| ... }
    #   parse(io, **options) {|row| ... }
    #
    # Parses +string+ or +io+ using the specified +options+.
    #
    # - Argument +string+ should be a \String object;
    #   it will be put into a new StringIO object positioned at the beginning.
    # :include: ../doc/arguments/io.rdoc
    # - Argument +options+: see {Options for Parsing}[#class-CSV-label-Options+for+Parsing]
    #
    # ====== Without Option +headers+
    #
    # Without {option +headers+}[#class-CSV-label-Option+headers] case.
    #
    # These examples assume prior execution of:
    #   string = "foo,0\nbar,1\nbaz,2\n"
    #   path = 't.csv'
    #   File.write(path, string)
    #
    # ---
    #
    # With no block given, returns an \Array of Arrays formed from the source.
    #
    # Parse a \String:
    #   a_of_a = CSV.parse(string)
    #   a_of_a # => [["foo", "0"], ["bar", "1"], ["baz", "2"]]
    #
    # Parse an open \File:
    #   a_of_a = File.open(path) do |file|
    #     CSV.parse(file)
    #   end
    #   a_of_a # => [["foo", "0"], ["bar", "1"], ["baz", "2"]]
    #
    # ---
    #
    # With a block given, calls the block with each parsed row:
    #
    # Parse a \String:
    #   CSV.parse(string) {|row| p row }
    #
    # Output:
    #   ["foo", "0"]
    #   ["bar", "1"]
    #   ["baz", "2"]
    #
    # Parse an open \File:
    #   File.open(path) do |file|
    #     CSV.parse(file) {|row| p row }
    #   end
    #
    # Output:
    #   ["foo", "0"]
    #   ["bar", "1"]
    #   ["baz", "2"]
    #
    # ====== With Option +headers+
    #
    # With {option +headers+}[#class-CSV-label-Option+headers] case.
    #
    # These examples assume prior execution of:
    #   string = "Name,Count\nfoo,0\nbar,1\nbaz,2\n"
    #   path = 't.csv'
    #   File.write(path, string)
    #
    # ---
    #
    # With no block given, returns a CSV::Table object formed from the source.
    #
    # Parse a \String:
    #   csv_table = CSV.parse(string, headers: ['Name', 'Count'])
    #   csv_table # => #<CSV::Table mode:col_or_row row_count:5>
    #
    # Parse an open \File:
    #   csv_table = File.open(path) do |file|
    #     CSV.parse(file, headers: ['Name', 'Count'])
    #   end
    #   csv_table # => #<CSV::Table mode:col_or_row row_count:4>
    #
    # ---
    #
    # With a block given, calls the block with each parsed row,
    # which has been formed into a CSV::Row object:
    #
    # Parse a \String:
    #   CSV.parse(string, headers: ['Name', 'Count']) {|row| p row }
    #
    # Output:
    #   # <CSV::Row "Name":"foo" "Count":"0">
    #   # <CSV::Row "Name":"bar" "Count":"1">
    #   # <CSV::Row "Name":"baz" "Count":"2">
    #
    # Parse an open \File:
    #   File.open(path) do |file|
    #     CSV.parse(file, headers: ['Name', 'Count']) {|row| p row }
    #   end
    #
    # Output:
    #   # <CSV::Row "Name":"foo" "Count":"0">
    #   # <CSV::Row "Name":"bar" "Count":"1">
    #   # <CSV::Row "Name":"baz" "Count":"2">
    #
    # ---
    #
    # Raises an exception if the argument is not a \String object or \IO object:
    #   # Raises NoMethodError (undefined method `close' for :foo:Symbol)
    #   CSV.parse(:foo)
    def parse(str, **options, &block)
      csv = new(str, **options)

      return csv.each(&block) if block_given?

      # slurp contents, if no block is given
      begin
        csv.read
      ensure
        csv.close
      end
    end

    # :call-seq:
    #   CSV.parse_line(string) -> new_array or nil
    #   CSV.parse_line(io) -> new_array or nil
    #   CSV.parse_line(string, **options) -> new_array or nil
    #   CSV.parse_line(io, **options) -> new_array or nil
    #   CSV.parse_line(string, headers: true, **options) -> csv_row or nil
    #   CSV.parse_line(io, headers: true, **options) -> csv_row or nil
    #
    # Returns the data created by parsing the first line of +string+ or +io+
    # using the specified +options+.
    #
    # - Argument +string+ should be a \String object;
    #   it will be put into a new StringIO object positioned at the beginning.
    # :include: ../doc/arguments/io.rdoc
    # - Argument +options+: see {Options for Parsing}[#class-CSV-label-Options+for+Parsing]
    #
    # ====== Without Option +headers+
    #
    # Without option +headers+, returns the first row as a new \Array.
    #
    # These examples assume prior execution of:
    #   string = "foo,0\nbar,1\nbaz,2\n"
    #   path = 't.csv'
    #   File.write(path, string)
    #
    # Parse the first line from a \String object:
    #   CSV.parse_line(string) # => ["foo", "0"]
    #
    # Parse the first line from a File object:
    #   File.open(path) do |file|
    #     CSV.parse_line(file) # => ["foo", "0"]
    #   end # => ["foo", "0"]
    #
    # Returns +nil+ if the argument is an empty \String:
    #   CSV.parse_line('') # => nil
    #
    # ====== With Option +headers+
    #
    # With {option +headers+}[#class-CSV-label-Option+headers],
    # returns the first row as a CSV::Row object.
    #
    # These examples assume prior execution of:
    #   string = "Name,Count\nfoo,0\nbar,1\nbaz,2\n"
    #   path = 't.csv'
    #   File.write(path, string)
    #
    # Parse the first line from a \String object:
    #   CSV.parse_line(string, headers: true) # => #<CSV::Row "Name":"foo" "Count":"0">
    #
    # Parse the first line from a File object:
    #   File.open(path) do |file|
    #     CSV.parse_line(file, headers: true)
    #   end # => #<CSV::Row "Name":"foo" "Count":"0">
    #
    # ---
    #
    # Raises an exception if the argument is +nil+:
    #   # Raises ArgumentError (Cannot parse nil as CSV):
    #   CSV.parse_line(nil)
    #
    def parse_line(line, **options)
      new(line, **options).each.first
    end

    #
    # :call-seq:
    #   read(source, **options) -> array_of_arrays
    #   read(source, headers: true, **options) -> csv_table
    #
    # Opens the given +source+ with the given +options+ (see CSV.open),
    # reads the source (see CSV#read), and returns the result,
    # which will be either an \Array of Arrays or a CSV::Table.
    #
    # Without headers:
    #   string = "foo,0\nbar,1\nbaz,2\n"
    #   path = 't.csv'
    #   File.write(path, string)
    #   CSV.read(path) # => [["foo", "0"], ["bar", "1"], ["baz", "2"]]
    #
    # With headers:
    #   string = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   path = 't.csv'
    #   File.write(path, string)
    #   CSV.read(path, headers: true) # => #<CSV::Table mode:col_or_row row_count:4>
    def read(path, **options)
      open(path, **options) { |csv| csv.read }
    end

    # :call-seq:
    #   CSV.readlines(source, **options)
    #
    # Alias for CSV.read.
    def readlines(path, **options)
      read(path, **options)
    end

    # :call-seq:
    #   CSV.table(source, **options)
    #
    # Calls CSV.read with +source+, +options+, and certain default options:
    # - +headers+: +true+
    # - +converbers+: +:numeric+
    # - +header_converters+: +:symbol+
    #
    # Returns a CSV::Table object.
    #
    # Example:
    #   string = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   path = 't.csv'
    #   File.write(path, string)
    #   CSV.table(path # => #<CSV::Table mode:col_or_row row_count:4>
    def table(path, **options)
      default_options = {
        headers:           true,
        converters:        :numeric,
        header_converters: :symbol,
      }
      options = default_options.merge(options)
      read(path, **options)
    end
  end

  # :call-seq:
  #   CSV.new(string)
  #   CSV.new(io)
  #   CSV.new(string, **options)
  #   CSV.new(io, **options)
  #
  # Returns the new \CSV object created using +string+ or +io+
  # and the specified +options+.
  #
  # - Argument +string+ should be a \String object;
  #   it will be put into a new StringIO object positioned at the beginning.
  # :include: ../doc/arguments/io.rdoc
  # - Argument +options+: See:
  #   * {Options for Parsing}[#class-CSV-label-Options+for+Parsing]
  #   * {Options for Generating}[#class-CSV-label-Options+for+Generating]
  #   For performance reasons, the options cannot be overridden
  #   in a \CSV object, so those specified here will endure.
  #
  # In addition to the \CSV instance methods, several \IO methods are delegated.
  # See {Delegated Methods}[#class-CSV-label-Delegated+Methods].
  #
  # ---
  #
  # Create a \CSV object from a \String object:
  #   csv = CSV.new('foo,0')
  #   csv # => #<CSV io_type:StringIO encoding:UTF-8 lineno:0 col_sep:"," row_sep:"\n" quote_char:"\"">
  #
  # Create a \CSV object from a \File object:
  #   File.write('t.csv', 'foo,0')
  #   csv = CSV.new(File.open('t.csv'))
  #   csv # => #<CSV io_type:File io_path:"t.csv" encoding:UTF-8 lineno:0 col_sep:"," row_sep:"\n" quote_char:"\"">
  #
  # ---
  #
  # Raises an exception if the argument is +nil+:
  #   # Raises ArgumentError (Cannot parse nil as CSV):
  #   CSV.new(nil)
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
                 quote_empty: true,
                 write_converters: nil,
                 write_nil_value: nil,
                 write_empty_value: "",
                 strip: false)
    raise ArgumentError.new("Cannot parse nil as CSV") if data.nil?

    if data.is_a?(String)
      @io = StringIO.new(data)
      @io.set_encoding(encoding || data.encoding)
    else
      @io = data
    end
    @encoding = determine_encoding(encoding, internal_encoding)

    @base_fields_converter_options = {
      nil_value: nil_value,
      empty_value: empty_value,
    }
    @write_fields_converter_options = {
      nil_value: write_nil_value,
      empty_value: write_empty_value,
    }
    @initial_converters = converters
    @initial_header_converters = header_converters
    @initial_write_converters = write_converters

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
      strip: strip,
    }
    @parser = nil
    @parser_enumerator = nil
    @eof_error = nil

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
  # The encoded <tt>:col_sep</tt> used in parsing and writing.
  # See CSV::new for details.
  #
  def col_sep
    parser.column_separator
  end

  #
  # The encoded <tt>:row_sep</tt> used in parsing and writing.
  # See CSV::new for details.
  #
  def row_sep
    parser.row_separator
  end

  #
  # The encoded <tt>:quote_char</tt> used in parsing and writing.
  # See CSV::new for details.
  #
  def quote_char
    parser.quote_character
  end

  #
  # The limit for field size, if any.
  # See CSV::new for details.
  #
  def field_size_limit
    parser.field_size_limit
  end

  #
  # The regex marking a line as a comment.
  # See CSV::new for details.
  #
  def skip_lines
    parser.skip_lines
  end

  #
  # Returns the current list of converters in effect. See CSV::new for details.
  # Built-in converters will be returned by name, while others will be returned
  # as is.
  #
  def converters
    parser_fields_converter.map do |converter|
      name = Converters.rassoc(converter)
      name ? name.first : converter
    end
  end

  #
  # Returns +true+ if unconverted_fields() to parsed results.
  # See CSV::new for details.
  #
  def unconverted_fields?
    parser.unconverted_fields?
  end

  #
  # Returns +nil+ if headers will not be used, +true+ if they will but have not
  # yet been read, or the actual headers after they have been read.
  # See CSV::new for details.
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

  #
  # Returns +true+ if headers are written in output.
  # See CSV::new for details.
  #
  def write_headers?
    @writer_options[:write_headers]
  end

  #
  # Returns the current list of converters in effect for headers. See CSV::new
  # for details. Built-in converters will be returned by name, while others
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
  def_delegators :@io, :binmode, :close, :close_read, :close_write,
                       :closed?, :external_encoding, :fcntl,
                       :fileno, :flush, :fsync, :internal_encoding,
                       :isatty, :pid, :pos, :pos=, :reopen,
                       :seek, :string, :sync, :sync=, :tell,
                       :truncate, :tty?

  def binmode?
    if @io.respond_to?(:binmode?)
      @io.binmode?
    else
      false
    end
  end

  def flock(*args)
    raise NotImplementedError unless @io.respond_to?(:flock)
    @io.flock(*args)
  end

  def ioctl(*args)
    raise NotImplementedError unless @io.respond_to?(:ioctl)
    @io.ioctl(*args)
  end

  def path
    @io.path if @io.respond_to?(:path)
  end

  def stat(*args)
    raise NotImplementedError unless @io.respond_to?(:stat)
    @io.stat(*args)
  end

  def to_i
    raise NotImplementedError unless @io.respond_to?(:to_i)
    @io.to_i
  end

  def to_io
    @io.respond_to?(:to_io) ? @io.to_io : @io
  end

  def eof?
    return false if @eof_error
    begin
      parser_enumerator.peek
      false
    rescue MalformedCSVError => error
      @eof_error = error
      false
    rescue StopIteration
      true
    end
  end
  alias_method :eof, :eof?

  # Rewinds the underlying IO object and resets CSV's lineno() counter.
  def rewind
    @parser = nil
    @parser_enumerator = nil
    @eof_error = nil
    @writer.rewind if @writer
    @io.rewind
  end

  ### End Delegation ###

  #
  # The primary write method for wrapped Strings and IOs, +row+ (an Array or
  # CSV::Row) is converted to CSV and appended to the data source. When a
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
  # and is expected to return the converted value or the field itself. If your
  # block takes two arguments, it will also be passed a CSV::FieldInfo Struct,
  # containing details about the field. Again, the block should return a
  # converted field or the field itself.
  #
  def convert(name = nil, &converter)
    parser_fields_converter.add_converter(name, &converter)
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
    parser_enumerator.each(&block)
  end

  # :call-seq:
  #     read
  #
  # Forms the remaining rows from +self+ into:
  # - A CSV::Table object, if headers are in use.
  # - An Array of Arrays, otherwise.
  #
  # The data source must be open for reading.
  #
  # Without headers:
  #   string = "foo,0\nbar,1\nbaz,2\n"
  #   path = 't.csv'
  #   File.write(path, string)
  #   csv = CSV.open(path)
  #   csv.read # => [["foo", "0"], ["bar", "1"], ["baz", "2"]]
  #
  # With headers:
  #   string = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
  #   path = 't.csv'
  #   File.write(path, string)
  #   csv = CSV.open(path, headers: true)
  #   csv.read # => #<CSV::Table mode:col_or_row row_count:4>
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
    if @eof_error
      eof_error, @eof_error = @eof_error, nil
      raise eof_error
    end
    begin
      parser_enumerator.next
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
    str = ["#<", self.class.to_s, " io_type:"]
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
  # if +headers+ is passed as +true+, returning the converted field set. Any
  # converter that changes the field into something other than a String halts
  # the pipeline of conversion for that field. This is primarily an efficiency
  # shortcut.
  #
  def convert_fields(fields, headers = false)
    if headers
      header_fields_converter.convert(fields, nil, 0)
    else
      parser_fields_converter.convert(fields, @headers, lineno)
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

  def parser_fields_converter
    @parser_fields_converter ||= build_parser_fields_converter
  end

  def build_parser_fields_converter
    specific_options = {
      builtin_converters: Converters,
    }
    options = @base_fields_converter_options.merge(specific_options)
    build_fields_converter(@initial_converters, options)
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
    build_fields_converter(@initial_header_converters, options)
  end

  def writer_fields_converter
    @writer_fields_converter ||= build_writer_fields_converter
  end

  def build_writer_fields_converter
    build_fields_converter(@initial_write_converters,
                           @write_fields_converter_options)
  end

  def build_fields_converter(initial_converters, options)
    fields_converter = FieldsConverter.new(options)
    normalize_converters(initial_converters).each do |name, converter|
      fields_converter.add_converter(name, &converter)
    end
    fields_converter
  end

  def parser
    @parser ||= Parser.new(@io, parser_options)
  end

  def parser_options
    @parser_options.merge(header_fields_converter: header_fields_converter,
                          fields_converter: parser_fields_converter)
  end

  def parser_enumerator
    @parser_enumerator ||= parser.parse
  end

  def writer
    @writer ||= Writer.new(@io, writer_options)
  end

  def writer_options
    @writer_options.merge(header_fields_converter: header_fields_converter,
                          fields_converter: writer_fields_converter)
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
