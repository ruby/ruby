# -*- coding: utf-8 -*-
# frozen_string_literal: false

begin
  require "zlib"
rescue LoadError
end

require_relative "helper"
require "tempfile"

class TestCSVFeatures < Test::Unit::TestCase
  extend DifferentOFS

  TEST_CASES = [ [%Q{a,b},               ["a", "b"]],
                 [%Q{a,"""b"""},         ["a", "\"b\""]],
                 [%Q{a,"""b"},           ["a", "\"b"]],
                 [%Q{a,"b"""},           ["a", "b\""]],
                 [%Q{a,"\nb"""},         ["a", "\nb\""]],
                 [%Q{a,"""\nb"},         ["a", "\"\nb"]],
                 [%Q{a,"""\nb\n"""},     ["a", "\"\nb\n\""]],
                 [%Q{a,"""\nb\n""",\nc}, ["a", "\"\nb\n\"", nil]],
                 [%Q{a,,,},              ["a", nil, nil, nil]],
                 [%Q{,},                 [nil, nil]],
                 [%Q{"",""},             ["", ""]],
                 [%Q{""""},              ["\""]],
                 [%Q{"""",""},           ["\"",""]],
                 [%Q{,""},               [nil,""]],
                 [%Q{,"\r"},             [nil,"\r"]],
                 [%Q{"\r\n,"},           ["\r\n,"]],
                 [%Q{"\r\n,",},          ["\r\n,", nil]] ]

  def setup
    super
    @sample_data = <<-CSV
line,1,abc
line,2,"def\nghi"

line,4,jkl
    CSV
    @csv = CSV.new(@sample_data)
  end

  def test_col_sep
    [";", "\t"].each do |sep|
      TEST_CASES.each do |test_case|
        assert_equal( test_case.last.map { |t| t.tr(",", sep) unless t.nil? },
                      CSV.parse_line( test_case.first.tr(",", sep),
                                      col_sep: sep ) )
      end
    end
    assert_equal([",,,", nil], CSV.parse_line(",,,;", col_sep: ";"))
  end

  def test_row_sep
    error = assert_raise(CSV::MalformedCSVError) do
      CSV.parse_line("1,2,3\n,4,5\r\n", row_sep: "\r\n")
    end
    assert_equal("Unquoted fields do not allow \\r or \\n in line 1.",
                 error.message)
    assert_equal( ["1", "2", "3\n", "4", "5"],
                  CSV.parse_line(%Q{1,2,"3\n",4,5\r\n}, row_sep: "\r\n"))
  end

  def test_quote_char
    TEST_CASES.each do |test_case|
      assert_equal(test_case.last.map {|t| t.tr('"', "'") unless t.nil?},
                   CSV.parse_line(test_case.first.tr('"', "'"),
                                  quote_char: "'" ))
    end
  end

  def test_quote_char_special_regexp_char
    TEST_CASES.each do |test_case|
      assert_equal(test_case.last.map {|t| t.tr('"', "|") unless t.nil?},
                   CSV.parse_line(test_case.first.tr('"', "|"),
                                  quote_char: "|"))
    end
  end

  def test_quote_char_special_regexp_char_liberal_parsing
    TEST_CASES.each do |test_case|
      assert_equal(test_case.last.map {|t| t.tr('"', "|") unless t.nil?},
                   CSV.parse_line(test_case.first.tr('"', "|"),
                                  quote_char: "|",
                                  liberal_parsing: true))
    end
  end

  def test_csv_char_readers
    %w[col_sep row_sep quote_char].each do |reader|
      csv = CSV.new("abc,def", reader.to_sym => "|")
      assert_equal("|", csv.send(reader))
    end
  end

  def test_row_sep_auto_discovery
    ["\r\n", "\n", "\r"].each do |line_end|
      data       = "1,2,3#{line_end}4,5#{line_end}"
      discovered = CSV.new(data).row_sep
      assert_equal(line_end, discovered)
    end

    assert_equal("\n", CSV.new("\n\r\n\r").row_sep)

    assert_equal($/, CSV.new("").row_sep)

    assert_equal($/, CSV.new(STDERR).row_sep)
  end

  def test_line
    lines = [
      %Q(abc,def\n),
      %Q(abc,"d\nef"\n),
      %Q(abc,"d\r\nef"\n),
      %Q(abc,"d\ref")
    ]
    csv = CSV.new(lines.join(''))
    lines.each do |line|
      csv.shift
      assert_equal(line, csv.line)
    end
  end

  def test_lineno
    assert_equal(5, @sample_data.lines.to_a.size)

    4.times do |line_count|
      assert_equal(line_count, @csv.lineno)
      assert_not_nil(@csv.shift)
      assert_equal(line_count + 1, @csv.lineno)
    end
    assert_nil(@csv.shift)
  end

  def test_readline
    test_lineno

    @csv.rewind

    test_lineno
  end

  def test_unknown_options
    assert_raise_with_message(ArgumentError, /unknown keyword/) {
      CSV.new(@sample_data, unknown: :error)
    }
    assert_raise_with_message(ArgumentError, /unknown keyword/) {
      CSV.new(@sample_data, universal_newline: true)
    }
  end

  def test_skip_blanks
    assert_equal(4, @csv.to_a.size)

    @csv  = CSV.new(@sample_data, skip_blanks: true)

    count = 0
    @csv.each do |row|
      count += 1
      assert_equal("line", row.first)
    end
    assert_equal(3, count)
  end

  def test_csv_behavior_readers
    %w[ unconverted_fields return_headers write_headers
        skip_blanks        force_quotes ].each do |behavior|
      assert_not_predicate(CSV.new("abc,def"), "#{behavior}?", "Behavior defaulted to on.")
      csv = CSV.new("abc,def", behavior.to_sym => true)
      assert_predicate(csv, "#{behavior}?", "Behavior change now registered.")
    end
  end

  def test_converters_reader
    # no change
    assert_equal( [:integer],
                  CSV.new("abc,def", converters: [:integer]).converters )

    # just one
    assert_equal( [:integer],
                  CSV.new("abc,def", converters: :integer).converters )

    # expanded
    assert_equal( [:integer, :float],
                  CSV.new("abc,def", converters: :numeric).converters )

    # custom
    csv = CSV.new("abc,def", converters: [:integer, lambda {  }])
    assert_equal(2, csv.converters.size)
    assert_equal(:integer, csv.converters.first)
    assert_instance_of(Proc, csv.converters.last)
  end

  def test_header_converters_reader
    # no change
    hc = :header_converters
    assert_equal([:downcase], CSV.new("abc,def", hc => [:downcase]).send(hc))

    # just one
    assert_equal([:downcase], CSV.new("abc,def", hc => :downcase).send(hc))

    # custom
    csv = CSV.new("abc,def", hc => [:symbol, lambda {  }])
    assert_equal(2, csv.send(hc).size)
    assert_equal(:symbol, csv.send(hc).first)
    assert_instance_of(Proc, csv.send(hc).last)
  end

  # reported by Kev Jackson
  def test_failing_to_escape_col_sep
    assert_nothing_raised(Exception) { CSV.new(String.new, col_sep: "|") }
  end

  # reported by Chris Roos
  def test_failing_to_reset_headers_in_rewind
    csv = CSV.new("forename,surname", headers: true, return_headers: true)
    csv.each {|row| assert_predicate row, :header_row?}
    csv.rewind
    csv.each {|row| assert_predicate row, :header_row?}
  end

  def test_gzip_reader
    zipped = nil
    assert_nothing_raised(NoMethodError) do
      zipped = CSV.new(
                 Zlib::GzipReader.open(
                   File.join(File.dirname(__FILE__), "line_endings.gz")
                 )
               )
    end
    assert_equal("\r\n", zipped.row_sep)
  ensure
    zipped.close
  end if defined?(Zlib::GzipReader)

  def test_gzip_writer
    Tempfile.create(%w"temp .gz") {|tempfile|
      tempfile.close
      file = tempfile.path
      zipped = nil
      assert_nothing_raised(NoMethodError) do
        zipped = CSV.new(Zlib::GzipWriter.open(file))
      end
      zipped << %w[one two three]
      zipped << [1, 2, 3]
      zipped.close

      assert_include(Zlib::GzipReader.open(file) {|f| f.read},
                     $INPUT_RECORD_SEPARATOR, "@row_sep did not default")
    }
  end if defined?(Zlib::GzipWriter)

  def test_inspect_is_smart_about_io_types
    str = CSV.new("string,data").inspect
    assert_include(str, "io_type:StringIO", "IO type not detected.")

    str = CSV.new($stderr).inspect
    assert_include(str, "io_type:$stderr", "IO type not detected.")

    Tempfile.create(%w"temp .csv") {|tempfile|
      tempfile.close
      path = tempfile.path
      File.open(path, "w") { |csv| csv << "one,two,three\n1,2,3\n" }
      str  = CSV.open(path) { |csv| csv.inspect }
      assert_include(str, "io_type:File", "IO type not detected.")
    }
  end

  def test_inspect_shows_key_attributes
    str = @csv.inspect
    %w[lineno col_sep row_sep quote_char].each do |attr_name|
      assert_match(/\b#{attr_name}:[^\s>]+/, str)
    end
  end

  def test_inspect_shows_headers_when_available
    csv = CSV.new("one,two,three\n1,2,3\n", headers: true)
    assert_include(csv.inspect, "headers:true", "Header hint not shown.")
    csv.shift  # load headers
    assert_match(/headers:\[[^\]]+\]/, csv.inspect)
  end

  def test_inspect_encoding_is_ascii_compatible
    csv = CSV.new("one,two,three\n1,2,3\n".encode("UTF-16BE"))
    assert_send([Encoding, :compatible?,
                  Encoding.find("US-ASCII"), csv.inspect.encoding],
                "inspect() was not ASCII compatible.")
  end

  def test_version
    assert_not_nil(CSV::VERSION)
    assert_instance_of(String, CSV::VERSION)
    assert_predicate(CSV::VERSION, :frozen?)
    assert_match(/\A\d\.\d\.\d\z/, CSV::VERSION)
  end

  def test_accepts_comment_skip_lines_option
    assert_nothing_raised(ArgumentError) do
      CSV.new(@sample_data, :skip_lines => /\A\s*#/)
    end
  end

  def test_accepts_comment_defaults_to_nil
    c = CSV.new(@sample_data)
    assert_nil(c.skip_lines)
  end

  class RegexStub
  end

  def test_requires_skip_lines_to_call_match
    regex_stub = RegexStub.new
    csv = CSV.new(@sample_data, :skip_lines => regex_stub)
    assert_raise_with_message(ArgumentError, /skip_lines/) do
      csv.shift
    end
  end

  class Matchable
    def initialize(pattern)
      @pattern = pattern
    end

    def match(line)
      @pattern.match(line)
    end
  end

  def test_skip_lines_match
    csv = <<-CSV.chomp
1
# 2
3
# 4
    CSV
    assert_equal([["1"], ["3"]],
                 CSV.parse(csv, :skip_lines => Matchable.new(/\A#/)))
  end

  def test_comment_rows_are_ignored
    sample_data = "line,1,a\n#not,a,line\nline,2,b\n   #also,no,line"
    c = CSV.new sample_data, :skip_lines => /\A\s*#/
    assert_equal [["line", "1", "a"], ["line", "2", "b"]], c.each.to_a
  end

  def test_comment_rows_are_ignored_with_heredoc
    sample_data = <<~EOL
      1,foo
      .2,bar
      3,baz
    EOL

    c = CSV.new(sample_data, skip_lines: ".")
    assert_equal [["1", "foo"], ["3", "baz"]], c.each.to_a
  end

  def test_quoted_skip_line_markers_are_ignored
    sample_data = "line,1,a\n\"#not\",a,line\nline,2,b"
    c = CSV.new sample_data, :skip_lines => /\A\s*#/
    assert_equal [["line", "1", "a"], ["#not", "a", "line"], ["line", "2", "b"]], c.each.to_a
  end

  def test_string_works_like_a_regexp
    sample_data = "line,1,a\n#(not,a,line\nline,2,b\n   also,#no,line"
    c = CSV.new sample_data, :skip_lines => "#"
    assert_equal [["line", "1", "a"], ["line", "2", "b"]], c.each.to_a
  end

  def test_table_nil_equality
    assert_nothing_raised(NoMethodError) { CSV.parse("test", headers: true) == nil }
  end

  # non-seekable input stream for testing https://github.com/ruby/csv/issues/44
  class DummyIO
    extend Forwardable
    def_delegators :@io, :gets, :read, :pos, :eof?  # no seek or rewind!
    def initialize(data)
      @io = StringIO.new(data)
    end
  end

  def test_line_separator_autodetection_for_non_seekable_input_lf
    c = CSV.new(DummyIO.new("one,two,three\nfoo,bar,baz\n"))
    assert_equal [["one", "two", "three"], ["foo", "bar", "baz"]], c.each.to_a
  end

  def test_line_separator_autodetection_for_non_seekable_input_cr
    c = CSV.new(DummyIO.new("one,two,three\rfoo,bar,baz\r"))
    assert_equal [["one", "two", "three"], ["foo", "bar", "baz"]], c.each.to_a
  end

  def test_line_separator_autodetection_for_non_seekable_input_cr_lf
    c = CSV.new(DummyIO.new("one,two,three\r\nfoo,bar,baz\r\n"))
    assert_equal [["one", "two", "three"], ["foo", "bar", "baz"]], c.each.to_a
  end

  def test_line_separator_autodetection_for_non_seekable_input_1024_over_lf
    table = (1..10).map { |row| (1..200).map { |col| "row#{row}col#{col}" }.to_a }.to_a
    input = table.map { |line| line.join(",") }.join("\n")
    c = CSV.new(DummyIO.new(input))
    assert_equal table, c.each.to_a
  end

  def test_line_separator_autodetection_for_non_seekable_input_1024_over_cr_lf
    table = (1..10).map { |row| (1..200).map { |col| "row#{row}col#{col}" }.to_a }.to_a
    input = table.map { |line| line.join(",") }.join("\r\n")
    c = CSV.new(DummyIO.new(input))
    assert_equal table, c.each.to_a
  end

  def test_line_separator_autodetection_for_non_seekable_input_many_cr_only
    # input with lots of CRs (to make sure no bytes are lost due to look-ahead)
    c = CSV.new(DummyIO.new("foo\r" + "\r" * 9999 + "bar\r"))
    assert_equal [["foo"]] + [[]] * 9999 + [["bar"]], c.each.to_a
  end
end
