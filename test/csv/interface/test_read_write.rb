# frozen_string_literal: false

require_relative "../helper"

class TestCSVInterfaceReadWrite < Test::Unit::TestCase
  extend DifferentOFS

  def test_filter
    input = <<-CSV.freeze
1;2;3
4;5
    CSV
    output = ""
    CSV.filter(input, output,
               in_col_sep: ";",
               out_col_sep: ",",
               converters: :all) do |row|
      row.map! {|n| n * 2}
      row << "Added\r"
    end
    assert_equal(<<-CSV, output)
2,4,6,"Added\r"
8,10,"Added\r"
    CSV
  end

  def test_filter_headers_true
    input = <<-CSV.freeze
Name,Value
foo,0
bar,1
baz,2
    CSV
    output = ""
    CSV.filter(input, output, headers: true) do |row|
      row[0] += "X"
      row[1] = row[1].to_i + 1
    end
    assert_equal(<<-CSV, output)
fooX,1
barX,2
bazX,3
    CSV
  end

  def test_filter_headers_true_write_headers
    input = <<-CSV.freeze
Name,Value
foo,0
bar,1
baz,2
    CSV
    output = ""
    CSV.filter(input, output, headers: true, out_write_headers: true) do |row|
      if row.is_a?(Array)
        row[0] += "X"
        row[1] += "Y"
      else
        row[0] += "X"
        row[1] = row[1].to_i + 1
      end
    end
    assert_equal(<<-CSV, output)
NameX,ValueY
fooX,1
barX,2
bazX,3
    CSV
  end

  def test_filter_headers_array_write_headers
    input = <<-CSV.freeze
foo,0
bar,1
baz,2
    CSV
    output = ""
    CSV.filter(input, output,
               headers: ["Name", "Value"],
               out_write_headers: true) do |row|
      row[0] += "X"
      row[1] = row[1].to_i + 1
    end
    assert_equal(<<-CSV, output)
Name,Value
fooX,1
barX,2
bazX,3
    CSV
  end

  def test_instance_same
    data = ""
    assert_equal(CSV.instance(data, col_sep: ";").object_id,
                 CSV.instance(data, col_sep: ";").object_id)
  end

  def test_instance_append
    output = ""
    CSV.instance(output, col_sep: ";") << ["a", "b", "c"]
    assert_equal(<<-CSV, output)
a;b;c
    CSV
    CSV.instance(output, col_sep: ";") << [1, 2, 3]
    assert_equal(<<-CSV, output)
a;b;c
1;2;3
    CSV
  end

  def test_instance_shortcut
    assert_equal(CSV.instance,
                 CSV {|csv| csv})
  end
end
