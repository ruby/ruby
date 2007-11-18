require 'test/unit'
require 'stringio'
dir = File.expand_path(__FILE__)
2.times {dir = File.dirname(dir)}
$:.replace([File.join(dir, "ruby")] | $:)
require 'ut_eof'

class TestStringIO < Test::Unit::TestCase
  include TestEOF
  def open_file(content)
    f = StringIO.new(content)
    yield f
  end
  alias open_file_rw open_file

  include TestEOF::Seek

  def test_truncate
    io = StringIO.new("")
    io.puts "abc"
    io.truncate(0)
    io.puts "def"
    assert_equal("\0\0\0\0def\n", io.string, "[ruby-dev:24190]")
  end

  def test_seek_beyond_eof
    io = StringIO.new
    n = 100
    io.seek(n)
    io.print "last"
    assert_equal("\0" * n + "last", io.string, "[ruby-dev:24194]")
  end

  def test_overwrite
    stringio = StringIO.new
    responses = ['', 'just another ruby', 'hacker']
    responses.each do |resp|
      stringio.puts(resp)
      stringio.rewind
    end
    assert_equal("hacker\nother ruby\n", stringio.string, "[ruby-core:3836]")
  end
end
