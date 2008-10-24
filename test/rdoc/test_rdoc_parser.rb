require 'rubygems'
require 'minitest/unit'
require 'rdoc/parser'
require 'rdoc/parser/ruby'

class TestRDocParser < MiniTest::Unit::TestCase
  def test_can_parse
    assert_equal(RDoc::Parser.can_parse(__FILE__), RDoc::Parser::Ruby)

    readme_file_name = File.join(File.dirname(__FILE__), "..", "README.txt")

    unless File.exist? readme_file_name then # HACK for tests in trunk :/
      readme_file_name = File.join File.dirname(__FILE__), '..', '..', 'README'
    end

    assert_equal(RDoc::Parser.can_parse(readme_file_name), RDoc::Parser::Simple)

    binary_file_name = File.join(File.dirname(__FILE__), "binary.dat")
    assert_equal(RDoc::Parser.can_parse(binary_file_name), nil)
  end
end

MiniTest::Unit.autorun
