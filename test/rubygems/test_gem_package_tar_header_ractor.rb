# frozen_string_literal: true

require_relative "package/tar_test_case"

unless Gem::Package::TarTestCase.instance_methods.include?(:assert_ractor)
  require "core_assertions"
  Gem::Package::TarTestCase.include Test::Unit::CoreAssertions
end

class TestGemPackageTarHeaderRactor < Gem::Package::TarTestCase
  ASSERT_HEADERS_EQUAL = <<~RUBY
    def assert_headers_equal(expected, actual)
      expected = expected.to_s unless String === expected
      actual = actual.to_s unless String === actual

      fields = %w[
        name 100
        mode 8
        uid 8
        gid 8
        size 12
        mtime 12
        checksum 8
        typeflag 1
        linkname 100
        magic 6
        version 2
        uname 32
        gname 32
        devmajor 8
        devminor 8
        prefix 155
      ]

      offset = 0

      until fields.empty? do
        name = fields.shift
        length = fields.shift.to_i

        if name == "checksum"
          chksum_off = offset
          offset += length
          next
        end

        assert_equal expected[offset, length], actual[offset, length]

        offset += length
      end

      assert_equal expected[chksum_off, 8], actual[chksum_off, 8]
    end
  RUBY

  SETUP = <<~RUBY
    header = {
      name: "x",
      mode: 0o644,
      uid: 1000,
      gid: 10_000,
      size: 100,
      mtime: 12_345,
      typeflag: "0",
      linkname: "link",
      uname: "user",
      gname: "group",
      devmajor: 1,
      devminor: 2,
      prefix: "y",
    }

    tar_header = Gem::Package::TarHeader.new header
  RUBY

  def test_decode_in_ractor
    assert_ractor(ASSERT_HEADERS_EQUAL + SETUP + <<~RUBY, require: ["rubygems/package", "stringio"])
      new_header = Ractor.new(tar_header.to_s) do |str|
        Gem::Package::TarHeader.from StringIO.new str
      end.value

      assert_headers_equal tar_header, new_header
    RUBY
  end

  def test_encode_in_ractor
    assert_ractor(ASSERT_HEADERS_EQUAL + SETUP + <<~RUBY, require: ["rubygems/package", "stringio"])
      header_bytes = tar_header.to_s

      new_header_bytes = Ractor.new(header_bytes) do |str|
        new_header = Gem::Package::TarHeader.from StringIO.new str
        new_header.to_s
      end.value

      assert_headers_equal header_bytes, new_header_bytes
    RUBY
  end
end
