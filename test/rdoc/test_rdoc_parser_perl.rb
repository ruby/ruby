require 'stringio'
require 'tempfile'
require 'rubygems'
require 'minitest/unit'
require 'rdoc/options'
require 'rdoc/parser/perl'

class TestRdocParserPerlPOD < MiniTest::Unit::TestCase

  def setup
    @tempfile = Tempfile.new self.class.name
    filename = @tempfile.path

    @top_level = RDoc::TopLevel.new filename
    @fn = filename
    @options = RDoc::Options.new
    @stats = RDoc::Stats.new 0
  end

  def teardown
    @tempfile.close
  end

  def test_uncommented_perl
    content = <<-EOF
while (<>) {
  tr/a-z/A-Z;
  print
}
    EOF

    comment =  util_get_comment content
    assert_equal "", comment
  end

  def test_perl_without_pod
    content = <<-EOF
#!/usr/local/bin/perl
#
#This is a pointless perl program because it does -p.
#
while(<>) {print;}:
    EOF

    comment = util_get_comment content
    assert_equal "", comment
  end

  def test_simple_pod_no_structure
    content = <<-EOF
=begin pod

This just contains plain old documentation

=end
    EOF
    comment = util_get_comment content
    assert_equal "\nThis just contains plain old documentation\n\n", comment
  end

  # Get the comment of the @top_level when it has processed the input.
  def util_get_comment(content)
    parser = util_parser content
    parser.scan.comment
  end

  # create a new parser with the supplied content.
  def util_parser(content)
    RDoc::Parser::PerlPOD.new @top_level, @fn, content, @options, @stats
  end

end

MiniTest::Unit.autorun
