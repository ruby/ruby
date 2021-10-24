# frozen_string_literal: false

require_relative "../helper"

class TestCSVInterfaceWrite < Test::Unit::TestCase
  extend DifferentOFS

  def setup
    super
    @output = Tempfile.new(["interface-write", ".csv"])
  end

  def teardown
    @output.close(true)
    super
  end

  def test_generate_default
    csv_text = CSV.generate do |csv|
      csv << [1, 2, 3] << [4, nil, 5]
    end
    assert_equal(<<-CSV, csv_text)
1,2,3
4,,5
    CSV
  end

  if respond_to?(:ractor)
    ractor
    def test_generate_default_in_ractor
      ractor = Ractor.new do
        CSV.generate do |csv|
          csv << [1, 2, 3] << [4, nil, 5]
        end
      end
      assert_equal(<<-CSV, ractor.take)
1,2,3
4,,5
      CSV
    end
  end

  def test_generate_append
    csv_text = <<-CSV
1,2,3
4,,5
    CSV
    CSV.generate(csv_text) do |csv|
      csv << ["last", %Q{"row"}]
    end
    assert_equal(<<-CSV, csv_text)
1,2,3
4,,5
last,"""row"""
    CSV
  end

  def test_generate_no_new_line
    csv_text = CSV.generate("test") do |csv|
      csv << ["row"]
    end
    assert_equal(<<-CSV, csv_text)
testrow
    CSV
  end

  def test_generate_line_col_sep
    line = CSV.generate_line(["1", "2", "3"], col_sep: ";")
    assert_equal(<<-LINE, line)
1;2;3
    LINE
  end

  def test_generate_line_row_sep
    line = CSV.generate_line(["1", "2"], row_sep: nil)
    assert_equal(<<-LINE.chomp, line)
1,2
    LINE
  end

  def test_generate_line_shortcut
    line = ["1", "2", "3"].to_csv(col_sep: ";")
    assert_equal(<<-LINE, line)
1;2;3
    LINE
  end

  def test_headers_detection
    headers = ["a", "b", "c"]
    CSV.open(@output.path, "w", headers: true) do |csv|
      csv << headers
      csv << ["1", "2", "3"]
      assert_equal(headers, csv.headers)
    end
  end

  def test_lineno
    CSV.open(@output.path, "w") do |csv|
      n_lines = 20
      n_lines.times do
        csv << ["a", "b", "c"]
      end
      assert_equal(n_lines, csv.lineno)
    end
  end

  def test_append_row
    CSV.open(@output.path, "wb") do |csv|
      csv <<
        CSV::Row.new([], ["1", "2", "3"]) <<
        CSV::Row.new([], ["a", "b", "c"])
    end
    assert_equal(<<-CSV, File.read(@output.path, mode: "rb"))
1,2,3
a,b,c
    CSV
  end


  if respond_to?(:ractor)
    ractor
    def test_append_row_in_ractor
      ractor = Ractor.new(@output.path) do |path|
        CSV.open(path, "wb") do |csv|
          csv <<
            CSV::Row.new([], ["1", "2", "3"]) <<
            CSV::Row.new([], ["a", "b", "c"])
        end
      end
      ractor.take
      assert_equal(<<-CSV, File.read(@output.path, mode: "rb"))
1,2,3
a,b,c
      CSV
    end
  end

  def test_append_hash
    CSV.open(@output.path, "wb", headers: true) do |csv|
      csv << [:a, :b, :c]
      csv << {a: 1, b: 2, c: 3}
      csv << {a: 4, b: 5, c: 6}
    end
    assert_equal(<<-CSV, File.read(@output.path, mode: "rb"))
a,b,c
1,2,3
4,5,6
    CSV
  end

  def test_append_hash_headers_array
    CSV.open(@output.path, "wb", headers: [:b, :a, :c]) do |csv|
      csv << {a: 1, b: 2, c: 3}
      csv << {a: 4, b: 5, c: 6}
    end
    assert_equal(<<-CSV, File.read(@output.path, mode: "rb"))
2,1,3
5,4,6
    CSV
  end

  def test_append_hash_headers_string
    CSV.open(@output.path, "wb", headers: "b|a|c", col_sep: "|") do |csv|
      csv << {"a" => 1, "b" => 2, "c" => 3}
      csv << {"a" => 4, "b" => 5, "c" => 6}
    end
    assert_equal(<<-CSV, File.read(@output.path, mode: "rb"))
2|1|3
5|4|6
    CSV
  end

  def test_write_headers
    CSV.open(@output.path,
             "wb",
             headers:       "b|a|c",
             write_headers: true,
             col_sep:       "|" ) do |csv|
      csv << {"a" => 1, "b" => 2, "c" => 3}
      csv << {"a" => 4, "b" => 5, "c" => 6}
    end
    assert_equal(<<-CSV, File.read(@output.path, mode: "rb"))
b|a|c
2|1|3
5|4|6
    CSV
  end

  def test_write_headers_empty
    CSV.open(@output.path,
             "wb",
             headers:       "b|a|c",
             write_headers: true,
             col_sep:       "|" ) do |csv|
    end
    assert_equal(<<-CSV, File.read(@output.path, mode: "rb"))
b|a|c
    CSV
  end

  def test_options_not_modified
    options = {}.freeze
    CSV.generate(**options) {}
    CSV.generate_line([], **options)
    CSV.filter("", "", **options)
    CSV.instance("", **options)
  end
end
