# frozen_string_literal: true

require_relative "package/tar_test_case"

unless Gem::Package::TarTestCase.method_defined?(:assert_ractor)
  require "core_assertions"
  Gem::Package::TarTestCase.include Test::Unit::CoreAssertions
end

class TestGemPackageTarHeaderRactor < Gem::Package::TarTestCase
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
    # Move this require to arguments of assert_ractor after Ruby 4.0 or updating core_assertions.rb at Ruby 3.4.
    require "stringio"
    # Remove this after Ruby 4.0 or updating core_assertions.rb at Ruby 3.4.
    class Ractor; alias value take unless method_defined?(:value); end
  RUBY

  def test_decode_in_ractor
    assert_ractor(SETUP + <<~RUBY, require: "rubygems/package", require_relative: "package/tar_test_case")
      include Gem::Package::TarTestMethods

      new_header = Ractor.new(tar_header.to_s) do |str|
        Gem::Package::TarHeader.from StringIO.new str
      end.value

      assert_headers_equal tar_header, new_header
    RUBY
  end

  def test_encode_in_ractor
    assert_ractor(SETUP + <<~RUBY, require: "rubygems/package", require_relative: "package/tar_test_case")
      include Gem::Package::TarTestMethods

      header_bytes = tar_header.to_s

      new_header_bytes = Ractor.new(header_bytes) do |str|
        new_header = Gem::Package::TarHeader.from StringIO.new str
        new_header.to_s
      end.value

      assert_headers_equal header_bytes, new_header_bytes
    RUBY
  end
end unless RUBY_PLATFORM.match?(/mingw|mswin/)
