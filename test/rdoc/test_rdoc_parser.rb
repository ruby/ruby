require 'rdoc/parser'

class TestRDocParser < Test::Unit::TestCase
  def test_can_parse
    assert_equal(RDoc::Parser.can_parse(__FILE__), RDoc::Parser::Ruby)

    readme_file_name = File.join(File.dirname(__FILE__), "..", "README.txt")

    unless File.exist? readme_file_name then
      readme_file_name = File.join File.dirname(__FILE__), '..', '..', 'README'
    end

    assert_equal(RDoc::Parser.can_parse(readme_file_name), RDoc::Parser::Simple)

    binary_file_name = File.join(File.dirname(__FILE__), "binary.dat")
    assert_equal(RDoc::Parser.can_parse(binary_file_name), nil)
  end
end
