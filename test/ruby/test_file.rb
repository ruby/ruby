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
        assert_raise(Errno::EACCES) {File.unlink(filename)}
      else
	assert_nothing_raised {File.unlink(filename)}
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
    assert(File.fnmatch('\[1\]' , '[1]'))
    assert(File.fnmatch('*?', 'a'))
    assert(File.fnmatch('*/', 'a/'))
    assert(File.fnmatch('\[1\]' , '[1]', File::FNM_PATHNAME))
    assert(File.fnmatch('*?', 'a', File::FNM_PATHNAME))
    assert(File.fnmatch('*/', 'a/', File::FNM_PATHNAME))
  end
end
