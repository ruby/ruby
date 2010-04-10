require 'rubygems'
require 'minitest/autorun'
require 'rdoc/parser'
require 'rdoc/parser/ruby'
require 'tmpdir'

class TestRDocParser < MiniTest::Unit::TestCase

  def setup
    @RP = RDoc::Parser
    @binary_dat = File.expand_path '../binary.dat', __FILE__
  end

  def test_class_binary_eh_erb
    erb = File.join Dir.tmpdir, "test_rdoc_parser_#{$$}.erb"
    open erb, 'wb' do |io|
      io.write 'blah blah <%= stuff %> <% more stuff %>'
    end

    assert @RP.binary?(erb)

    erb_rb = File.join Dir.tmpdir, "test_rdoc_parser_#{$$}.erb.rb"
    open erb_rb, 'wb' do |io|
      io.write 'blah blah <%= stuff %>'
    end

    refute @RP.binary?(erb_rb)
  ensure
    File.unlink erb
    File.unlink erb_rb if erb_rb
  end

  def test_class_binary_eh_marshal
    marshal = File.join Dir.tmpdir, "test_rdoc_parser_#{$$}.marshal"
    open marshal, 'wb' do |io|
      io.write Marshal.dump('')
      io.write 'lots of text ' * 500
    end

    assert @RP.binary?(marshal)
  ensure
    File.unlink marshal
  end

  def test_class_can_parse
    assert_equal @RP.can_parse(__FILE__), @RP::Ruby

    readme_file_name = File.expand_path '../test.txt', __FILE__

    assert_equal @RP::Simple, @RP.can_parse(readme_file_name)

    assert_nil @RP.can_parse(@binary_dat)

    jtest_file_name = File.expand_path '../test.ja.txt', __FILE__
    assert_equal @RP::Simple, @RP.can_parse(jtest_file_name)

    jtest_rdoc_file_name = File.expand_path '../test.ja.rdoc', __FILE__
    assert_equal @RP::Simple, @RP.can_parse(jtest_rdoc_file_name)

    readme_file_name = File.expand_path '../README', __FILE__
    assert_equal @RP::Simple, @RP.can_parse(readme_file_name)
  end

  ##
  # Selenium hides a .jar file using a .txt extension.

  def test_class_can_parse_zip
    hidden_zip = File.expand_path '../hidden.zip.txt', __FILE__
    assert_nil @RP.can_parse(hidden_zip)
  end

  def test_class_for_binary
    rp = @RP.dup

    def rp.can_parse(*args) nil end

    assert_nil @RP.for(nil, @binary_dat, nil, nil, nil)
  end

end

