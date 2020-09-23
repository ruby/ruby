# frozen_string_literal: true
require 'rubygems/package/tar_test_case'
require 'rubygems/package'

class TestGemPackageTarHeader < Gem::Package::TarTestCase

  def setup
    super

    header = {
      :name     => 'x',
      :mode     => 0644,
      :uid      => 1000,
      :gid      => 10000,
      :size     => 100,
      :mtime    => 12345,
      :typeflag => '0',
      :linkname => 'link',
      :uname    => 'user',
      :gname    => 'group',
      :devmajor => 1,
      :devminor => 2,
      :prefix   => 'y',
    }

    @tar_header = Gem::Package::TarHeader.new header
  end

  def test_self_from
    io = TempIO.new @tar_header.to_s

    new_header = Gem::Package::TarHeader.from io

    assert_headers_equal @tar_header, new_header
  ensure
    io.close!
  end

  def test_initialize
    assert_equal '',      @tar_header.checksum, 'checksum'
    assert_equal 1,       @tar_header.devmajor, 'devmajor'
    assert_equal 2,       @tar_header.devminor, 'devminor'
    assert_equal 10000,   @tar_header.gid,      'gid'
    assert_equal 'group', @tar_header.gname,    'gname'
    assert_equal 'link',  @tar_header.linkname, 'linkname'
    assert_equal 'ustar', @tar_header.magic,    'magic'
    assert_equal 0644,    @tar_header.mode,     'mode'
    assert_equal 12345,   @tar_header.mtime,    'mtime'
    assert_equal 'x',     @tar_header.name,     'name'
    assert_equal 'y',     @tar_header.prefix,   'prefix'
    assert_equal 100,     @tar_header.size,     'size'
    assert_equal '0',     @tar_header.typeflag, 'typeflag'
    assert_equal 1000,    @tar_header.uid,      'uid'
    assert_equal 'user',  @tar_header.uname,    'uname'
    assert_equal '00',    @tar_header.version,  'version'

    refute_empty @tar_header, 'empty'
  end

  def test_initialize_bad
    assert_raises ArgumentError do
      Gem::Package::TarHeader.new :name => '', :size => '', :mode => ''
    end

    assert_raises ArgumentError do
      Gem::Package::TarHeader.new :name => '', :size => '', :prefix => ''
    end

    assert_raises ArgumentError do
      Gem::Package::TarHeader.new :name => '', :prefix => '', :mode => ''
    end

    assert_raises ArgumentError do
      Gem::Package::TarHeader.new :prefix => '', :size => '', :mode => ''
    end
  end

  def test_initialize_typeflag
    header = {
      :mode     => '',
      :name     => '',
      :prefix   => '',
      :size     => '',
      :typeflag => '',
    }

    tar_header = Gem::Package::TarHeader.new header

    assert_equal '0', tar_header.typeflag
  end

  def test_empty_eh
    refute_empty @tar_header

    @tar_header = Gem::Package::TarHeader.new :name => 'x', :prefix => '',
                                              :mode => 0, :size => 0,
                                              :empty => true

    assert_empty @tar_header
  end

  def test_equals2
    assert_equal @tar_header, @tar_header
    assert_equal @tar_header, @tar_header.dup
  end

  def test_to_s
    expected = <<-EOF.split("\n").join
x\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000
\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000
\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000
\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000
\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000
\000\000\000\0000000644\0000001750\0000023420\00000000000144\00000000030071
\000012467\000 0link\000\000\000\000\000\000\000\000\000\000\000\000\000\000
\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000
\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000
\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000
\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000
\000\000\000\000\000\000ustar\00000user\000\000\000\000\000\000\000\000\000
\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000
group\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000
\000\000\000\000\000\000\000\000\0000000001\0000000002\000y\000\000\000\000
\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000
\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000
\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000
\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000
\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000
\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000
\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000
\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000
\000\000\000\000\000\000\000\000\000\000
    EOF

    assert_headers_equal expected, @tar_header
  end

  def test_update_checksum
    assert_equal '', @tar_header.checksum

    @tar_header.update_checksum

    assert_equal '012467', @tar_header.checksum
  end

  def test_from_bad_octal
    test_cases = [
      "00000006,44\000", # bogus character
      "00000006789\000", # non-octal digit
      "+0000001234\000", # positive sign
      "-0000001000\000", # negative sign
      "0x000123abc\000", # radix prefix
    ]

    test_cases.each do |val|
      header_s = @tar_header.to_s
      # overwrite the size field
      header_s[124, 12] = val
      io = TempIO.new header_s
      assert_raises ArgumentError do
        Gem::Package::TarHeader.from io
      end
      io.close!
    end
  end

  def test_big_uid_gid
    stream = StringIO.new(
      <<-EOF.dup.force_encoding('binary').split("\n").join
GeoIP2-City_20190528/
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x000000755\x00\x80\x00
\x00\x00v\xB2Z\x9E\x80\x00\x00\x00v\xB2Z\x9E00000000000\x0013473270100\x00015424
\x00 5\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00ustar  \x00
tjmather\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00tjmather\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00
      EOF
    )

    tar_header = Gem::Package::TarHeader.from stream

    assert_equal 1991400094, tar_header.uid
    assert_equal 1991400094, tar_header.gid

    assert_equal 'GeoIP2-City_20190528/', tar_header.name
    assert_equal 0755, tar_header.mode
    assert_equal 0, tar_header.size
    assert_equal 1559064640, tar_header.mtime
    assert_equal 6932, tar_header.checksum
  end

  def test_spaces_in_headers
    stream = StringIO.new(
      <<-EOF.dup.force_encoding('binary').split("\n").join
Access_Points_09202018.csv
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00100777 \x00     0 \x00     0 \x00       4357 13545040367  104501
\x000
      EOF
    )

    tar_header = Gem::Package::TarHeader.from stream

    assert_equal 0, tar_header.uid
    assert_equal 0, tar_header.gid
  end

end
