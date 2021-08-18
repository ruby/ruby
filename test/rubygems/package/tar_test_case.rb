# frozen_string_literal: true
require_relative '../helper'
require 'rubygems/package'

##
# A test case for Gem::Package::Tar* classes

class Gem::Package::TarTestCase < Gem::TestCase
  def ASCIIZ(str, length)
    str + "\0" * (length - str.length)
  end

  def SP(s)
    s + " "
  end

  def SP_Z(s)
    s + " \0"
  end

  def Z(s)
    s + "\0"
  end

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

      assert_equal expected[offset, length], actual[offset, length],
                   "Field #{name} of the tar header differs."

      offset += length
    end

    assert_equal expected[chksum_off, 8], actual[chksum_off, 8]
  end

  def calc_checksum(header)
    sum = header.unpack("C*").inject{|s,a| s + a }
    SP(Z(to_oct(sum, 6)))
  end

  def header(type, fname, dname, length, mode, mtime, checksum = nil, linkname = "")
    checksum ||= " " * 8

    arr = [                  # struct tarfile_entry_posix
      ASCIIZ(fname, 100),    # char name[100];     ASCII + (Z unless filled)
      Z(to_oct(mode, 7)),    # char mode[8];       0 padded, octal null
      Z(to_oct(0, 7)),       # char uid[8];        ditto
      Z(to_oct(0, 7)),       # char gid[8];        ditto
      Z(to_oct(length, 11)), # char size[12];      0 padded, octal, null
      Z(to_oct(mtime, 11)),  # char mtime[12];     0 padded, octal, null
      checksum,              # char checksum[8];   0 padded, octal, null, space
      type,                  # char typeflag[1];   file: "0"  dir: "5"
      ASCIIZ(linkname, 100), # char linkname[100]; ASCII + (Z unless filled)
      "ustar\0",             # char magic[6];      "ustar\0"
      "00",                  # char version[2];    "00"
      ASCIIZ("wheel", 32),   # char uname[32];     ASCIIZ
      ASCIIZ("wheel", 32),   # char gname[32];     ASCIIZ
      Z(to_oct(0, 7)),       # char devmajor[8];   0 padded, octal, null
      Z(to_oct(0, 7)),       # char devminor[8];   0 padded, octal, null
      ASCIIZ(dname, 155), # char prefix[155];   ASCII + (Z unless filled)
    ]

    h = arr.join
    ret = h + "\0" * (512 - h.size)
    assert_equal(512, ret.size)
    ret
  end

  def tar_dir_header(name, prefix, mode, mtime)
    h = header("5", name, prefix, 0, mode, mtime)
    checksum = calc_checksum(h)
    header("5", name, prefix, 0, mode, mtime, checksum)
  end

  def tar_file_header(fname, dname, mode, length, mtime)
    h = header("0", fname, dname, length, mode, mtime)
    checksum = calc_checksum(h)
    header("0", fname, dname, length, mode, mtime, checksum)
  end

  def tar_symlink_header(fname, prefix, mode, mtime, linkname)
    h = header("2", fname, prefix, 0, mode, mtime, nil, linkname)
    checksum = calc_checksum(h)
    header("2", fname, prefix, 0, mode, mtime, checksum, linkname)
  end

  def to_oct(n, pad_size)
    "%0#{pad_size}o" % n
  end

  def util_entry(tar)
    io = TempIO.new tar

    header = Gem::Package::TarHeader.from io

    Gem::Package::TarReader::Entry.new header, io
  end

  def util_dir_entry
    util_entry tar_dir_header("foo", "bar", 0, Time.now)
  end

  def util_symlink_entry
    util_entry tar_symlink_header("foo", "bar", 0, Time.now, "link")
  end
end
