require File.expand_path('../helper', __FILE__)
require 'rake/private_reader'

class TestPrivateAttrs < Rake::TestCase

  class Sample
    include Rake::PrivateReader

    private_reader :reader, :a

    def initialize
      @reader = :RVALUE
    end

    def get_reader
      reader
    end

  end

  def setup
    super
    @sample = Sample.new
  end

  def test_private_reader_is_private
    assert_private do @sample.reader end
    assert_private do @sample.a end
  end

  def test_private_reader_returns_data
    assert_equal :RVALUE, @sample.get_reader
  end

  private

  def assert_private
    ex = assert_raises(NoMethodError) do yield end
    assert_match(/private/, ex.message)
  end

end
