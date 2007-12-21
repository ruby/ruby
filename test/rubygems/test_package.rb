#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'test/unit'
require 'stringio'
require 'fileutils'

require 'rubygems'
require 'rubygems/package'

class File

  # straight from setup.rb
  def self.dir?(path)
    # for corrupted windows stat()
    File.directory?((path[-1,1] == '/') ? path : path + '/')
  end

  def self.read_b(name)
    File.open(name, "rb"){|f| f.read}
  end

end

class TarTestCase < Test::Unit::TestCase

  undef_method :default_test if instance_methods.include? 'default_test' or
                                instance_methods.include? :default_test

  def assert_headers_equal(h1, h2)
    fields = %w[name 100 mode 8 uid 8 gid 8 size 12 mtime 12 checksum 8
                    typeflag 1 linkname 100 magic 6 version 2 uname 32 
                    gname 32 devmajor 8 devminor 8 prefix 155]
    offset = 0
    until fields.empty?
      name = fields.shift
      length = fields.shift.to_i
      if name == "checksum"
        chksum_off = offset
        offset += length
        next
      end
      assert_equal(h1[offset, length], h2[offset, length], 
                         "Field #{name} of the tar header differs.")
      offset += length
    end
    assert_equal(h1[chksum_off, 8], h2[chksum_off, 8])
  end

  def tar_file_header(fname, dname, mode, length)
    h = header("0", fname, dname, length, mode)
    checksum = calc_checksum(h)
    header("0", fname, dname, length, mode, checksum)
  end

  def tar_dir_header(name, prefix, mode)
    h = header("5", name, prefix, 0, mode)
    checksum = calc_checksum(h)
    header("5", name, prefix, 0, mode, checksum)
  end

  def header(type, fname, dname, length, mode, checksum = nil)
    checksum ||= " " * 8

    arr = [                  # struct tarfile_entry_posix
      ASCIIZ(fname, 100),    # char name[100];     ASCII + (Z unless filled)
      Z(to_oct(mode, 7)),    # char mode[8];       0 padded, octal null
      Z(to_oct(0, 7)),       # char uid[8];        ditto
      Z(to_oct(0, 7)),       # char gid[8];        ditto
      Z(to_oct(length, 11)), # char size[12];      0 padded, octal, null
      Z(to_oct(0, 11)),      # char mtime[12];     0 padded, octal, null
      checksum,              # char checksum[8];   0 padded, octal, null, space
      type,                  # char typeflag[1];   file: "0"  dir: "5"
      "\0" * 100,            # char linkname[100]; ASCII + (Z unless filled)
      "ustar\0",             # char magic[6];      "ustar\0"
      "00",                  # char version[2];    "00"
      ASCIIZ("wheel", 32),   # char uname[32];     ASCIIZ
      ASCIIZ("wheel", 32),   # char gname[32];     ASCIIZ
      Z(to_oct(0, 7)),       # char devmajor[8];   0 padded, octal, null
      Z(to_oct(0, 7)),       # char devminor[8];   0 padded, octal, null
      ASCIIZ(dname, 155)     # char prefix[155];   ASCII + (Z unless filled)
    ]

    format = "C100C8C8C8C12C12C8CC100C6C2C32C32C8C8C155"
    h = if RUBY_VERSION >= "1.9" then
          arr.join
        else
          arr = arr.join("").split(//).map{|x| x[0]}
          arr.pack format
        end
    ret = h + "\0" * (512 - h.size)
    assert_equal(512, ret.size)
    ret
  end

  def calc_checksum(header)
    sum = header.unpack("C*").inject{|s,a| s + a}
    SP(Z(to_oct(sum, 6)))
  end

  def to_oct(n, pad_size)
        "%0#{pad_size}o" % n
  end

  def ASCIIZ(str, length)
    str + "\0" * (length - str.length)
  end

  def SP(s)
    s + " "
  end

  def Z(s)
    s + "\0"
  end

  def SP_Z(s)
    s + " \0"
  end

end

class TestTarHeader < TarTestCase

  def test_arguments_are_checked
    e = ArgumentError
    gpth = Gem::Package::TarHeader
    assert_raises(e) { gpth.new :name=>"", :size=>"", :mode=>"" }
    assert_raises(e) { gpth.new :name=>"", :size=>"", :prefix=>"" }
    assert_raises(e) { gpth.new :name=>"", :prefix=>"", :mode=>"" }
    assert_raises(e) { gpth.new :prefix=>"", :size=>"", :mode=>"" }
  end

  def test_basic_headers
    header = Gem::Package::TarHeader.new(:name => "bla", :mode => 012345,
                                         :size => 10, :prefix => "").to_s
    assert_headers_equal(tar_file_header("bla", "", 012345, 10), header.to_s)
    header = Gem::Package::TarHeader.new(:name => "bla", :mode => 012345,
                                         :size => 0, :prefix => "",
                                         :typeflag => "5" ).to_s
    assert_headers_equal(tar_dir_header("bla", "", 012345), header)
  end

  def test_long_name_works
    header = Gem::Package::TarHeader.new(:name => "a" * 100, :mode => 012345, 
                                         :size => 10, :prefix => "").to_s
    assert_headers_equal(tar_file_header("a" * 100, "", 012345, 10), header)

    header = Gem::Package::TarHeader.new(:name => "a" * 100, :mode => 012345,
                                         :size => 10, :prefix => "bb" * 60).to_s
    assert_headers_equal(tar_file_header("a" * 100, "bb" * 60, 012345, 10),
                         header)
  end

  def test_new_from_stream
    header = tar_file_header("a" * 100, "", 012345, 10)
    h = nil
    header = StringIO.new header
    assert_nothing_raised{ h = Gem::Package::TarHeader.new_from_stream header }
    assert_equal("a" * 100, h.name)
    assert_equal(012345, h.mode)
    assert_equal(10, h.size)
    assert_equal("", h.prefix)
    assert_equal("ustar", h.magic)
  end

end

class TestTarInput < TarTestCase

  # Sometimes the setgid bit doesn't take.  Don't know if this
  # is a problem on all systems, or just some.  But for now, we
  # will ignore it in the tests.
  SETGID_BIT = 02000

  def setup
    FileUtils.mkdir_p "data__"
    inner_tar = tar_file_header("bla", "", 0612, 10)
    inner_tar += "0123456789" + "\0" * 502
    inner_tar += tar_file_header("foo", "", 0636, 5)
    inner_tar += "01234" + "\0" * 507
    inner_tar += tar_dir_header("__dir__", "", 0600)
    inner_tar += "\0" * 1024
    str = StringIO.new ""
    begin
      os = Zlib::GzipWriter.new str
      os.write inner_tar
    ensure
      os.finish
    end
    str.rewind
    File.open("data__/bla.tar", "wb") do |f|
      f.write tar_file_header("data.tar.gz", "", 0644, str.string.size)
      f.write str.string
      f.write "\0" * ((512 - (str.string.size % 512)) % 512 )
      @spec = Gem::Specification.new do |spec|
        spec.author = "Mauricio :)"
      end
      meta = @spec.to_yaml
      f.write tar_file_header("metadata", "", 0644, meta.size)
      f.write meta + "\0" * (1024 - meta.size) 
      f.write "\0" * 1024
    end
    @file = "data__/bla.tar"
    @entry_names = %w{bla foo __dir__}
    @entry_sizes = [10, 5, 0]
    #FIXME: are these modes system dependent?
    @entry_modes = [0100612, 0100636, 040600]
    @entry_files = %w{data__/bla data__/foo}
    @entry_contents = %w[0123456789 01234]
  end

  def teardown
    #            FileUtils.rm_rf "data__"
  end

  def test_each_works
    Gem::Package::TarInput.open(@file) do |is|
      count = 0

      is.each_with_index do |entry, i|
        count = i

        assert_kind_of(Gem::Package::TarReader::Entry, entry)
        assert_equal(@entry_names[i], entry.name)
        assert_equal(@entry_sizes[i], entry.size)
      end

      assert_equal 2, count

      assert_equal @spec, is.metadata
    end
  end

  def test_extract_entry_works
    Gem::Package::TarInput.open(@file) do |is|
      assert_equal @spec, is.metadata
      count = 0

      is.each_with_index do |entry, i|
        count = i
        is.extract_entry "data__", entry
        name = File.join("data__", entry.name)

        if entry.is_directory?
          assert File.dir?(name)
        else
          assert File.file?(name) 
          assert_equal(@entry_sizes[i], File.stat(name).size)
          #FIXME: win32? !!
        end

        unless ::Config::CONFIG["arch"] =~ /msdos|win32/i
          assert_equal(@entry_modes[i],
                       File.stat(name).mode & (~SETGID_BIT))
        end
      end

      assert_equal 2, count
    end

    @entry_files.each_with_index do |x, i|
      assert(File.file?(x))
      assert_equal(@entry_contents[i], File.read_b(x))
    end
  end

end

class TestTarOutput < TarTestCase

  def setup
    FileUtils.mkdir_p "data__", :verbose=>false
    @file = "data__/bla2.tar"
  end

  def teardown
    FileUtils.rm_rf "data__"
  end

  def test_file_looks_good
    Gem::Package::TarOutput.open(@file) do |os|
      os.metadata = "bla".to_yaml
    end
    f = File.open(@file, "rb")
    Gem::Package::TarReader.new(f) do |is|
      i = 0
      is.each do |entry|
        case i
        when 0
          assert_equal("data.tar.gz", entry.name)
        when 1
          assert_equal("metadata.gz", entry.name)
          gzis = Zlib::GzipReader.new entry
          assert_equal("bla".to_yaml, gzis.read)
          gzis.close
        end
        i += 1
      end
      assert_equal(2, i)
    end
  ensure
    f.close
  end

end

class TestTarReader < TarTestCase

  def test_eof_works
    str = tar_file_header("bar", "baz", 0644, 0)
    Gem::Package::TarReader.new(StringIO.new(str)) do |is|
      is.each_entry do |entry|
        assert_kind_of(Gem::Package::TarReader::Entry, entry)
        data = entry.read
        assert_equal(nil, data)
        assert_equal(nil, entry.read(10))
        assert_equal(nil, entry.read)
        assert_equal(nil, entry.getc)
        assert_equal(true, entry.eof?)
      end
    end
    str = tar_dir_header("foo", "bar", 012345)
    Gem::Package::TarReader.new(StringIO.new(str)) do |is|
      is.each_entry do |entry|
        assert_kind_of(Gem::Package::TarReader::Entry, entry)
        data = entry.read
        assert_equal(nil, data)
        assert_equal(nil, entry.read(10))
        assert_equal(nil, entry.read)
        assert_equal(nil, entry.getc)
        assert_equal(true, entry.eof?)
      end
    end
    str = tar_dir_header("foo", "bar", 012345)
    str += tar_file_header("bar", "baz", 0644, 0)
    str += tar_file_header("bar", "baz", 0644, 0)
    Gem::Package::TarReader.new(StringIO.new(str)) do |is|
      is.each_entry do |entry|
        assert_kind_of(Gem::Package::TarReader::Entry, entry)
        data = entry.read
        assert_equal(nil, data)
        assert_equal(nil, entry.read(10))
        assert_equal(nil, entry.read)
        assert_equal(nil, entry.getc)
        assert_equal(true, entry.eof?)
      end
    end
  end

  def test_multiple_entries
    str = tar_file_header("lib/foo", "", 010644, 10) + "\0" * 512
    str += tar_file_header("bar", "baz", 0644, 0)
    str += tar_dir_header("foo", "bar", 012345)
    str += "\0" * 1024
    names = %w[lib/foo bar foo]
    prefixes = ["", "baz", "bar"]
    modes = [010644, 0644, 012345]
    sizes = [10, 0, 0]
    isdir = [false, false, true]
    isfile = [true, true, false]
    Gem::Package::TarReader.new(StringIO.new(str)) do |is|
      i = 0
      is.each_entry do |entry|
        assert_kind_of(Gem::Package::TarReader::Entry, entry)
        assert_equal(names[i], entry.name)
        assert_equal(prefixes[i], entry.prefix)
        assert_equal(sizes[i], entry.size)
        assert_equal(modes[i], entry.mode)
        assert_equal(isdir[i], entry.is_directory?)
        assert_equal(isfile[i], entry.is_file?)
        if prefixes[i] != ""
          assert_equal(File.join(prefixes[i], names[i]),
                       entry.full_name)
        else
          assert_equal(names[i], entry.name)
        end
        i += 1
      end
      assert_equal(names.size, i) 
    end
  end

  def test_read_works
    contents = ('a'..'z').inject(""){|s,x| s << x * 100}
    str = tar_file_header("lib/foo", "", 010644, contents.size) + contents 
    str += "\0" * (512 - (str.size % 512))
    Gem::Package::TarReader.new(StringIO.new(str)) do |is|
      is.each_entry do |entry|
        assert_kind_of(Gem::Package::TarReader::Entry, entry)
        data = entry.read(3000) # bigger than contents.size
        assert_equal(contents, data)
        assert_equal(true, entry.eof?)
      end
    end
    Gem::Package::TarReader.new(StringIO.new(str)) do |is|
      is.each_entry do |entry|
        assert_kind_of(Gem::Package::TarReader::Entry, entry)
        data = entry.read(100)
        (entry.size - data.size).times {|i| data << entry.getc.chr }
        assert_equal(contents, data)
        assert_equal(nil, entry.read(10))
        assert_equal(true, entry.eof?)
      end
    end
    Gem::Package::TarReader.new(StringIO.new(str)) do |is|
      is.each_entry do |entry|
        assert_kind_of(Gem::Package::TarReader::Entry, entry)
        data = entry.read
        assert_equal(contents, data)
        assert_equal(nil, entry.read(10))
        assert_equal(nil, entry.read)
        assert_equal(nil, entry.getc)
        assert_equal(true, entry.eof?)
      end
    end
  end

  def test_rewind_entry_works
    content = ('a'..'z').to_a.join(" ")
    str = tar_file_header("lib/foo", "", 010644, content.size) + content + 
            "\0" * (512 - content.size)
    str << "\0" * 1024
    Gem::Package::TarReader.new(StringIO.new(str)) do |is|
      is.each_entry do |entry|
        3.times do 
          entry.rewind
          assert_equal(content, entry.read)
          assert_equal(content.size, entry.pos)
        end
      end
    end
  end

  def test_rewind_works
    content = ('a'..'z').to_a.join(" ")
    str = tar_file_header("lib/foo", "", 010644, content.size) + content + 
            "\0" * (512 - content.size)
    str << "\0" * 1024
    Gem::Package::TarReader.new(StringIO.new(str)) do |is|
      3.times do
        is.rewind
        i = 0
        is.each_entry do |entry|
          assert_equal(content, entry.read)
          i += 1
        end
        assert_equal(1, i)
      end
    end
  end

end

class TestTarWriter < TarTestCase

  class DummyIO
    attr_reader :data
    def initialize
      @data = ""
    end
    def write(dat)
      data << dat
      dat.size
    end
    def reset
      @data = ""
    end
  end

  def setup
    @data = "a" * 10
    @dummyos = DummyIO.new
    @os = Gem::Package::TarWriter.new(@dummyos)
  end

  def teardown
    @os.close
  end

  def test_add_file
    dummyos = StringIO.new
    class << dummyos
      def method_missing(meth, *a)
        self.string.send(meth, *a)
      end
    end
    os = Gem::Package::TarWriter.new dummyos
    content1 = ('a'..'z').to_a.join("")  # 26
    content2 = ('aa'..'zz').to_a.join("") # 1352
    Gem::Package::TarWriter.new(dummyos) do |os|
      os.add_file("lib/foo/bar", 0644) {|f| f.write "a" * 10 }
      os.add_file("lib/bar/baz", 0644) {|f| f.write content1 }
      os.add_file("lib/bar/baz", 0644) {|f| f.write content2 }
      os.add_file("lib/bar/baz", 0644) {|f| }
    end
    assert_headers_equal(tar_file_header("lib/foo/bar", "", 0644, 10),
                         dummyos[0,512])
    assert_equal("a" * 10 + "\0" * 502, dummyos[512,512])
    offset = 512 * 2
    [content1, content2, ""].each do |data|
      assert_headers_equal(tar_file_header("lib/bar/baz", "", 0644,
                                           data.size),
                                           dummyos[offset,512])
      offset += 512
      until !data || data == ""
        chunk = data[0,512]
        data[0,512] = ""
        assert_equal(chunk + "\0" * (512-chunk.size), 
                     dummyos[offset,512])
                     offset += 512
      end
    end
    assert_equal("\0" * 1024, dummyos[offset,1024])
  end

  def test_add_file_simple
    @dummyos.reset
    Gem::Package::TarWriter.new(@dummyos) do |os|
      os.add_file_simple("lib/foo/bar", 0644, 10) {|f| f.write "a" * 10 }
      os.add_file_simple("lib/bar/baz", 0644, 100) {|f| f.write "fillme"}
    end
    assert_headers_equal(tar_file_header("lib/foo/bar", "", 0644, 10),
                         @dummyos.data[0,512])
    assert_equal("a" * 10 + "\0" * 502, @dummyos.data[512,512])
    assert_headers_equal(tar_file_header("lib/bar/baz", "", 0644, 100), 
                         @dummyos.data[512*2,512])
    assert_equal("fillme" + "\0" * 506, @dummyos.data[512*3,512])
    assert_equal("\0" * 512, @dummyos.data[512*4, 512])
    assert_equal("\0" * 512, @dummyos.data[512*5, 512])
  end

  def test_add_file_tests_seekability
    assert_raises(Gem::Package::NonSeekableIO) do 
      @os.add_file("libdfdsfd", 0644) {|f| }
    end
  end

  def test_file_name_is_split_correctly
    # test insane file lengths, and
    #  a{100}/b{155}, etc
    @dummyos.reset
    names = ["a" * 155 + '/' + "b" * 100, "a" * 151 + "/" + ("qwer/" * 19) + "bla" ]
    o_names = ["b" * 100, "qwer/" * 19 + "bla"]
    o_prefixes = ["a" * 155, "a" * 151]
    names.each {|name| @os.add_file_simple(name, 0644, 10) { } }
    o_names.each_with_index do |nam, i|
      assert_headers_equal(tar_file_header(nam, o_prefixes[i], 0644, 10),
                           @dummyos.data[2*i*512,512])
    end
    assert_raises(Gem::Package::TooLongFileName) do
      @os.add_file_simple(File.join("a" * 152, "b" * 10, "a" * 92), 0644,10) {}
    end
    assert_raises(Gem::Package::TooLongFileName) do
      @os.add_file_simple(File.join("a" * 162, "b" * 10), 0644,10) {}
    end
    assert_raises(Gem::Package::TooLongFileName) do
      @os.add_file_simple(File.join("a" * 10, "b" * 110), 0644,10) {}
    end
  end

  def test_file_size_is_checked
    @dummyos.reset
    assert_raises(Gem::Package::TarWriter::FileOverflow) do 
      @os.add_file_simple("lib/foo/bar", 0644, 10) {|f| f.write "1" * 100}
    end
    assert_nothing_raised do
      @os.add_file_simple("lib/foo/bar", 0644, 10) {|f| }
    end
  end

  def test_write_data
    @dummyos.reset
    @os.add_file_simple("lib/foo/bar", 0644, 10) { |f| f.write @data }
    @os.flush
    assert_equal(@data + ("\0" * (512-@data.size)),
                 @dummyos.data[512,512])
  end

  def test_write_header
    @dummyos.reset
    @os.add_file_simple("lib/foo/bar", 0644, 0) { |f|  }
    @os.flush
    assert_headers_equal(tar_file_header("lib/foo/bar", "", 0644, 0),
                         @dummyos.data[0,512])
    @dummyos.reset
    @os.mkdir("lib/foo", 0644)
    assert_headers_equal(tar_dir_header("lib/foo", "", 0644),
                         @dummyos.data[0,512])
    @os.mkdir("lib/bar", 0644)
    assert_headers_equal(tar_dir_header("lib/bar", "", 0644),
                         @dummyos.data[512*1,512])
  end

  def test_write_operations_fail_after_closed
    @dummyos.reset
    @os.add_file_simple("sadd", 0644, 20) { |f| }
    @os.close
    assert_raises(Gem::Package::ClosedIO) { @os.flush }
    assert_raises(Gem::Package::ClosedIO) { @os.add_file("dfdsf", 0644){} }
    assert_raises(Gem::Package::ClosedIO) { @os.mkdir "sdfdsf", 0644 }
  end

end

