# frozen_string_literal: false

require_relative "../helper"

class TestCSVInterfaceRead < Test::Unit::TestCase
  extend DifferentOFS

  def setup
    super
    @data = ""
    @data << "1\t2\t3\r\n"
    @data << "4\t5\r\n"
    @input = Tempfile.new(["interface-read", ".csv"], binmode: true)
    @input << @data
    @input.rewind
    @rows = [
      ["1", "2", "3"],
      ["4", "5"],
    ]
  end

  def teardown
    @input.close(true)
    super
  end

  def test_foreach
    rows = []
    CSV.foreach(@input.path, col_sep: "\t", row_sep: "\r\n").each do |row|
      rows << row
    end
    assert_equal(@rows, rows)
  end

  def test_foreach_mode
    rows = []
    CSV.foreach(@input.path, "r", col_sep: "\t", row_sep: "\r\n").each do |row|
      rows << row
    end
    assert_equal(@rows, rows)
  end

  def test_foreach_enumurator
    rows = CSV.foreach(@input.path, col_sep: "\t", row_sep: "\r\n").to_a
    assert_equal(@rows, rows)
  end

  def test_closed?
    csv = CSV.open(@input.path, "r+", col_sep: "\t", row_sep: "\r\n")
    assert_not_predicate(csv, :closed?)
    csv.close
    assert_predicate(csv, :closed?)
  end

  def test_open_auto_close
    csv = nil
    CSV.open(@input.path) do |_csv|
      csv = _csv
    end
    assert_predicate(csv, :closed?)
  end

  def test_open_closed
    csv = nil
    CSV.open(@input.path) do |_csv|
      csv = _csv
      csv.close
    end
    assert_predicate(csv, :closed?)
  end

  def test_open_block_return_value
    return_value = CSV.open(@input.path) do
      "Return value."
    end
    assert_equal("Return value.", return_value)
  end

  def test_open_encoding_valid
    # U+1F600 GRINNING FACE
    # U+1F601 GRINNING FACE WITH SMILING EYES
    File.open(@input.path, "w") do |file|
      file << "\u{1F600},\u{1F601}"
    end
    CSV.open(@input.path, encoding: "utf-8") do |csv|
      assert_equal([["\u{1F600}", "\u{1F601}"]],
                   csv.to_a)
    end
  end

  def test_open_encoding_invalid
    # U+1F600 GRINNING FACE
    # U+1F601 GRINNING FACE WITH SMILING EYES
    File.open(@input.path, "w") do |file|
      file << "\u{1F600},\u{1F601}"
    end
    CSV.open(@input.path, encoding: "EUC-JP") do |csv|
      error = assert_raise(CSV::MalformedCSVError) do
        csv.shift
      end
      assert_equal("Invalid byte sequence in EUC-JP in line 1.",
                   error.message)
    end
  end

  def test_open_encoding_nonexistent
    _output, error = capture_io do
      CSV.open(@input.path, encoding: "nonexistent") do
      end
    end
    assert_equal("path:0: warning: Unsupported encoding nonexistent ignored\n",
                 error.gsub(/\A.+:\d+: /, "path:0: "))
  end

  def test_open_encoding_utf_8_with_bom
    # U+FEFF ZERO WIDTH NO-BREAK SPACE, BOM
    # U+1F600 GRINNING FACE
    # U+1F601 GRINNING FACE WITH SMILING EYES
    File.open(@input.path, "w") do |file|
      file << "\u{FEFF}\u{1F600},\u{1F601}"
    end
    CSV.open(@input.path, encoding: "bom|utf-8") do |csv|
      assert_equal([["\u{1F600}", "\u{1F601}"]],
                   csv.to_a)
    end
  end

  def test_parse
    assert_equal(@rows,
                 CSV.parse(@data, col_sep: "\t", row_sep: "\r\n"))
  end

  def test_parse_block
    rows = []
    CSV.parse(@data, col_sep: "\t", row_sep: "\r\n") do |row|
      rows << row
    end
    assert_equal(@rows, rows)
  end

  def test_parse_enumerator
    rows = CSV.parse(@data, col_sep: "\t", row_sep: "\r\n").to_a
    assert_equal(@rows, rows)
  end

  def test_parse_headers_only
    table = CSV.parse("a,b,c", headers: true)
    assert_equal([
                   ["a", "b", "c"],
                   [],
                 ],
                 [
                   table.headers,
                   table.each.to_a,
                 ])
  end

  def test_parse_line
    assert_equal(["1", "2", "3"],
                 CSV.parse_line("1;2;3", col_sep: ";"))
  end

  def test_parse_line_shortcut
    assert_equal(["1", "2", "3"],
                 "1;2;3".parse_csv(col_sep: ";"))
  end

  def test_parse_line_empty
    assert_equal(nil, CSV.parse_line(""))  # to signal eof
  end

  def test_parse_line_empty_line
    assert_equal([], CSV.parse_line("\n1,2,3"))
  end

  def test_read
    assert_equal(@rows,
                 CSV.read(@input.path, col_sep: "\t", row_sep: "\r\n"))
  end

  def test_readlines
    assert_equal(@rows,
                 CSV.readlines(@input.path, col_sep: "\t", row_sep: "\r\n"))
  end

  def test_open_read
    rows = CSV.open(@input.path, col_sep: "\t", row_sep: "\r\n") do |csv|
      csv.read
    end
    assert_equal(@rows, rows)
  end

  def test_open_readlines
    rows = CSV.open(@input.path, col_sep: "\t", row_sep: "\r\n") do |csv|
      csv.readlines
    end
    assert_equal(@rows, rows)
  end

  def test_table
    table = CSV.table(@input.path, col_sep: "\t", row_sep: "\r\n")
    assert_equal(CSV::Table.new([
                                  CSV::Row.new([:"1", :"2", :"3"], [4, 5, nil]),
                                ]),
                 table)
  end

  def test_shift  # aliased as gets() and readline()
    CSV.open(@input.path, "rb+", col_sep: "\t", row_sep: "\r\n") do |csv|
      rows = [
        csv.shift,
        csv.shift,
        csv.shift,
      ]
      assert_equal(@rows + [nil],
                   rows)
    end
  end

  def test_enumerator
    CSV.open(@input.path, col_sep: "\t", row_sep: "\r\n") do |csv|
      assert_equal(@rows, csv.each.to_a)
    end
  end

  def test_shift_and_each
    CSV.open(@input.path, col_sep: "\t", row_sep: "\r\n") do |csv|
      rows = []
      rows << csv.shift
      rows.concat(csv.each.to_a)
      assert_equal(@rows, rows)
    end
  end

  def test_each_twice
    CSV.open(@input.path, col_sep: "\t", row_sep: "\r\n") do |csv|
      assert_equal([
                     @rows,
                     [],
                   ],
                   [
                     csv.each.to_a,
                     csv.each.to_a,
                   ])
    end
  end

  def test_eof?
    eofs = []
    CSV.open(@input.path, col_sep: "\t", row_sep: "\r\n") do |csv|
      eofs << csv.eof?
      csv.shift
      eofs << csv.eof?
      csv.shift
      eofs << csv.eof?
    end
    assert_equal([false, false, true],
                 eofs)
  end

  def test_new_nil
    assert_raise_with_message ArgumentError, "Cannot parse nil as CSV" do
      CSV.new(nil)
    end
  end

  def test_options_not_modified
    options = {}.freeze
    CSV.foreach(@input.path, options)
    CSV.open(@input.path, options) {}
    CSV.parse("", options)
    CSV.parse_line("", options)
    CSV.read(@input.path, options)
    CSV.readlines(@input.path, options)
    CSV.table(@input.path, options)
  end
end
