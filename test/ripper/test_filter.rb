begin

require 'ripper'
require 'test/unit'

class TestRipper_Filter < Test::Unit::TestCase

  class Filter < Ripper::Filter
    def on_default(event, token, data)
      if data.empty?
        data[:filename] = filename rescue nil
        data[:lineno] = lineno
        data[:column] = column
        data[:token] = token
      end
      data
    end
  end

  def filename
    File.expand_path(__FILE__)
  end

  def test_filter_filename
    data = {}
    Filter.new(File.read(filename)).parse(data)
    assert_equal('-', data[:filename], "[ruby-dev:37856]")

    data = {}
    Filter.new(File.read(filename), filename).parse(data)
    assert_equal(filename, data[:filename])
  end

  def test_filter_lineno
    data = {}
    Filter.new(File.read(filename)).parse(data)
    assert_equal(1, data[:lineno])
  end

  def test_filter_column
    data = {}
    Filter.new(File.read(filename)).parse(data)
    assert_equal(0, data[:column])
  end

  def test_filter_token
    data = {}
    Filter.new(File.read(filename)).parse(data)
    assert_equal("begin", data[:token])
  end
end

rescue LoadError
end
