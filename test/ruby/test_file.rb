require 'test/unit'

$KCODE = 'none'

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
end
