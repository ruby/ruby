require 'tempfile'
require 'rubygems'
require 'minitest/autorun'
require 'rdoc/rdoc'

class TestRDocRDoc < MiniTest::Unit::TestCase

  def setup
    @rdoc = RDoc::RDoc.new
    @tempfile = Tempfile.new 'test_rdoc_rdoc'
  end

  def teardown
    @tempfile.close
  end

  def test_gather_files
    file = File.expand_path __FILE__
    assert_equal [file], @rdoc.gather_files([file, file])
  end

  def test_read_file_contents
    @tempfile.write "hi everybody"
    @tempfile.flush

    assert_equal "hi everybody", @rdoc.read_file_contents(@tempfile.path)
  end

  def test_read_file_contents_encoding
    skip "Encoding not implemented" unless defined? ::Encoding

    @tempfile.write "# coding: utf-8\nhi everybody"
    @tempfile.flush

    contents = @rdoc.read_file_contents @tempfile.path
    assert_equal "# coding: utf-8\nhi everybody", contents
    assert_equal Encoding::UTF_8, contents.encoding
  end

  def test_read_file_contents_encoding_fancy
    skip "Encoding not implemented" unless defined? ::Encoding

    @tempfile.write "# -*- coding: utf-8; fill-column: 74 -*-\nhi everybody"
    @tempfile.flush

    contents = @rdoc.read_file_contents @tempfile.path
    assert_equal("# -*- coding: utf-8; fill-column: 74 -*-\nhi everybody",
                 contents)
    assert_equal Encoding::UTF_8, contents.encoding
  end

  def test_remove_unparsable
    file_list = %w[
      blah.class
      blah.eps
      blah.erb
      blah.scpt.txt
      blah.ttf
      blah.yml
    ]

    assert_empty @rdoc.remove_unparseable file_list
  end

end

