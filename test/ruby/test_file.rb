require 'test/unit'
require 'tempfile'
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
end
