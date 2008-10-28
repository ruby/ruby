require 'test/unit'
require 'tempfile'
require_relative 'ut_eof'

class TestFile < Test::Unit::TestCase

  # I don't know Ruby's spec about "unlink-before-close" exactly.
  # This test asserts current behaviour.
  def test_unlink_before_close
    Dir.mktmpdir('rubytest-file') {|tmpdir|
      filename = tmpdir + '/' + File.basename(__FILE__) + ".#{$$}"
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
    }
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

  def test_truncate_wbuf
    f = Tempfile.new("test-truncate")
    f.print "abc"
    f.truncate(0)
    f.print "def"
    f.close
    assert_equal("\0\0\0def", File.read(f.path), "[ruby-dev:24191]")
  end

  def test_truncate_rbuf
    f = Tempfile.new("test-truncate")
    f.puts "abc"
    f.puts "def"
    f.close
    f.open
    assert_equal("abc\n", f.gets)
    f.truncate(3)
    assert_equal(nil, f.gets, "[ruby-dev:24197]")
  end

  def test_truncate_beyond_eof
    f = Tempfile.new("test-truncate")
    f.print "abc"
    f.truncate 10
    assert_equal("\0" * 7, f.read(100), "[ruby-dev:24532]")
  end

  def test_read_all_extended_file
    [nil, {:textmode=>true}, {:binmode=>true}].each do |mode|
      f = Tempfile.new("test-extended-file", mode)
      assert_nil(f.getc)
      open(f.path, "w") {|g| g.print "a" }
      assert_equal("a", f.read, "mode = <#{mode}>")
    end
  end

  def test_gets_extended_file
    [nil, {:textmode=>true}, {:binmode=>true}].each do |mode|
      f = Tempfile.new("test-extended-file", mode)
      assert_nil(f.getc)
      open(f.path, "w") {|g| g.print "a" }
      assert_equal("a", f.gets("a"), "mode = <#{mode}>")
    end
  end

  def test_gets_para_extended_file
    [nil, {:textmode=>true}, {:binmode=>true}].each do |mode|
      f = Tempfile.new("test-extended-file", mode)
      assert_nil(f.getc)
      open(f.path, "wb") {|g| g.print "\na" }
      assert_equal("a", f.gets(""), "mode = <#{mode}>")
    end
  end

  def test_each_char_extended_file
    [nil, {:textmode=>true}, {:binmode=>true}].each do |mode|
      f = Tempfile.new("test-extended-file", mode)
      assert_nil(f.getc)
      open(f.path, "w") {|g| g.print "a" }
      result = []
      f.each_char {|b| result << b }
      assert_equal([?a], result, "mode = <#{mode}>")
    end
  end

  def test_each_byte_extended_file
    [nil, {:textmode=>true}, {:binmode=>true}].each do |mode|
      f = Tempfile.new("test-extended-file", mode)
      assert_nil(f.getc)
      open(f.path, "w") {|g| g.print "a" }
      result = []
      f.each_byte {|b| result << b.chr }
      assert_equal([?a], result, "mode = <#{mode}>")
    end
  end

  def test_getc_extended_file
    [nil, {:textmode=>true}, {:binmode=>true}].each do |mode|
      f = Tempfile.new("test-extended-file", mode)
      assert_nil(f.getc)
      open(f.path, "w") {|g| g.print "a" }
      assert_equal(?a, f.getc, "mode = <#{mode}>")
    end
  end

  def test_getbyte_extended_file
    [nil, {:textmode=>true}, {:binmode=>true}].each do |mode|
      f = Tempfile.new("test-extended-file", mode)
      assert_nil(f.getc)
      open(f.path, "w") {|g| g.print "a" }
      assert_equal(?a, f.getbyte.chr, "mode = <#{mode}>")
    end
  end

  def test_s_chown
    assert_nothing_raised { File.chown -1, -1 }
    assert_nothing_raised { File.chown nil, nil }
  end

  def test_chown
    assert_nothing_raised {
      File.open(__FILE__) {|f| f.chown -1, -1 }
    }
    assert_nothing_raised("[ruby-dev:27140]") {
      File.open(__FILE__) {|f| f.chown nil, nil }
    }
  end

  def test_uninitialized
    assert_raise(TypeError) { File::Stat.allocate.readable? }
    assert_nothing_raised { File::Stat.allocate.inspect }
  end
end
