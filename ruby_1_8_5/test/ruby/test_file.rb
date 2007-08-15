require 'test/unit'
require 'tempfile'
$:.replace([File.dirname(File.expand_path(__FILE__))] | $:)
require 'ut_eof'

class TestFile < Test::Unit::TestCase

  # I don't know Ruby's spec about "unlink-before-close" exactly.
  # This test asserts current behaviour.
  def test_unlink_before_close
    filename = File.basename(__FILE__) + ".#{$$}"
    w = File.open(filename, "w")
    w << "foo"
    w.close
    r = File.open(filename, "r")
    begin
      if /(mswin|bccwin|mingw|emx)/ =~ RUBY_PLATFORM
	begin
	  File.unlink(filename)
	  assert(false)
	rescue Errno::EACCES
	  assert(true)
	end
      else
	File.unlink(filename)
	assert(true)
      end
    ensure
      r.close
      File.unlink(filename) if File.exist?(filename)
    end
  end

  include TestEOF
  def open_file(content)
    f = Tempfile.new("test-eof")
    f << content
    f.rewind
    yield f
  end
  alias open_file_rw open_file

  include TestEOF::Seek

  def test_fnmatch
    # from [ruby-dev:22815] and [ruby-dev:22819]
    assert(true, File.fnmatch('\[1\]' , '[1]'))
    assert(true, File.fnmatch('*?', 'a'))
  end

  def test_truncate_wbuf # [ruby-dev:24191]
    f = Tempfile.new("test-truncate")
    f.print "abc"
    f.truncate(0)
    f.print "def"
    f.close
    assert_equal("\0\0\0def", File.read(f.path))
  end

  def test_truncate_rbuf # [ruby-dev:24197]
    f = Tempfile.new("test-truncate")
    f.puts "abc"
    f.puts "def"
    f.close
    f.open
    assert_equal("abc\n", f.gets)
    f.truncate(3)
    assert_equal(nil, f.gets)
  end

  def test_read_all_extended_file
    f = Tempfile.new("test-extended-file")
    assert_nil(f.getc)
    open(f.path, "w") {|g| g.print "a" }
    assert_equal("a", f.read)
  end

  def test_gets_extended_file
    f = Tempfile.new("test-extended-file")
    assert_nil(f.getc)
    open(f.path, "w") {|g| g.print "a" }
    assert_equal("a", f.gets("a"))
  end

  def test_gets_para_extended_file
    f = Tempfile.new("test-extended-file")
    assert_nil(f.getc)
    open(f.path, "w") {|g| g.print "\na" }
    assert_equal("a", f.gets(""))
  end

  def test_each_byte_extended_file
    f = Tempfile.new("test-extended-file")
    assert_nil(f.getc)
    open(f.path, "w") {|g| g.print "a" }
    result = []
    f.each_byte {|b| result << b }
    assert_equal([?a], result)
  end

  def test_getc_extended_file
    f = Tempfile.new("test-extended-file")
    assert_nil(f.getc)
    open(f.path, "w") {|g| g.print "a" }
    assert_equal(?a, f.getc)
  end

end
