# frozen_string_literal: false
# $RoughId: test.rb,v 1.4 2001/07/13 15:38:27 knu Exp $
# $Id$

require 'test/unit'
require 'tempfile'

require 'digest'
%w[digest/md5 digest/rmd160 digest/sha1 digest/sha2 digest/bubblebabble digest/crc32 digest/blake3].each do |lib|
  begin
    require lib
  rescue LoadError
  end
end

module TestDigest
  Data1 = "abc"
  Data2 = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"

  def test_s_new
    self.class::DATA.each do |str, hexdigest|
      assert_raise(ArgumentError) { self.class::ALGO.new("") }
    end
  end

  def test_s_hexdigest
    self.class::DATA.each do |str, hexdigest|
      actual = self.class::ALGO.hexdigest(str)
      assert_equal(hexdigest, actual)
      assert_equal(Encoding::US_ASCII, actual.encoding)
    end
  end

  def test_s_base64digest
    self.class::DATA.each do |str, hexdigest|
      digest = [hexdigest].pack("H*")
      actual = self.class::ALGO.base64digest(str)
      assert_equal([digest].pack("m0"), actual)
      assert_equal(Encoding::US_ASCII, actual.encoding)
    end
  end

  def test_s_digest
    self.class::DATA.each do |str, hexdigest|
      digest = [hexdigest].pack("H*")
      actual = self.class::ALGO.digest(str)
      assert_equal(digest, actual)
      assert_equal(Encoding::BINARY, actual.encoding)
    end
  end

  def test_update
    # This test is also for digest() and hexdigest()

    str = "ABC"

    md = self.class::ALGO.new
    md.update str
    assert_equal(self.class::ALGO.hexdigest(str), md.hexdigest)
    assert_equal(self.class::ALGO.digest(str), md.digest)
  end

  def test_eq
    # This test is also for clone()

    md1 = self.class::ALGO.new
    md1 << "ABC"

    assert_equal(md1, md1.clone, self.class::ALGO)

    bug9913 = '[ruby-core:62967] [Bug #9913]'
    assert_not_equal(md1, nil, bug9913)

    md2 = self.class::ALGO.new
    md2 << "A"

    assert_not_equal(md1, md2, self.class::ALGO)

    md2 << "BC"

    assert_equal(md1, md2, self.class::ALGO)
  end

  def test_s_file
    Tempfile.create("test_digest_file", mode: File::BINARY) { |tmpfile|
      str = "hello, world.\r\n"
      tmpfile.print str
      tmpfile.close

      assert_equal self.class::ALGO.new.update(str), self.class::ALGO.file(tmpfile.path)
    }
  end

  def test_instance_eval
    assert_nothing_raised {
      self.class::ALGO.new.instance_eval { update "a" }
    }
  end

  def test_alignment
    md = self.class::ALGO.new
    assert_nothing_raised('#4320') {
      md.update('a' * 97)
      md.update('a' * 97)
      md.hexdigest
    }
  end

  def test_bubblebabble
    expected = "xirek-hasol-fumik-lanax"
    assert_equal expected, Digest.bubblebabble('message')
  end

  def test_bubblebabble_class
    expected = "xopoh-fedac-fenyh-nehon-mopel-nivor-lumiz-rypon-gyfot-cosyz-rimez-lolyv-pekyz-rosud-ricob-surac-toxox"
    assert_equal expected, Digest::SHA256.bubblebabble('message')
  end

  def test_bubblebabble_instance
    expected = "xumor-boceg-dakuz-sulic-gukoz-rutas-mekek-zovud-gunap-vabov-genin-rygyg-sanun-hykac-ruvah-dovah-huxex"

    hash = Digest::SHA256.new
    assert_equal expected, hash.bubblebabble
  end

  class TestMD5 < Test::Unit::TestCase
    include TestDigest
    ALGO = Digest::MD5
    DATA = {
      Data1 => "900150983cd24fb0d6963f7d28e17f72",
      Data2 => "8215ef0796a20bcaaae116d3876c664a",
    }
  end if defined?(Digest::MD5)

  class TestSHA1 < Test::Unit::TestCase
    include TestDigest
    ALGO = Digest::SHA1
    DATA = {
      Data1 => "a9993e364706816aba3e25717850c26c9cd0d89d",
      Data2 => "84983e441c3bd26ebaae4aa1f95129e5e54670f1",
    }
  end if defined?(Digest::SHA1)

  class TestSHA256 < Test::Unit::TestCase
    include TestDigest
    ALGO = Digest::SHA256
    DATA = {
      Data1 => "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      Data2 => "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
    }
  end if defined?(Digest::SHA256)

  class TestSHA384 < Test::Unit::TestCase
    include TestDigest
    ALGO = Digest::SHA384
    DATA = {
      Data1 => "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed"\
               "8086072ba1e7cc2358baeca134c825a7",
      Data2 => "3391fdddfc8dc7393707a65b1b4709397cf8b1d162af05abfe8f450de5f36bc6"\
               "b0455a8520bc4e6f5fe95b1fe3c8452b",
    }
  end if defined?(Digest::SHA384)

  class TestSHA512 < Test::Unit::TestCase
    include TestDigest
    ALGO = Digest::SHA512
    DATA = {
      Data1 => "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"\
               "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
      Data2 => "204a8fc6dda82f0a0ced7beb8e08a41657c16ef468b228a8279be331a703c335"\
               "96fd15c13b1b07f9aa1d3bea57789ca031ad85c7a71dd70354ec631238ca3445",
    }
  end if defined?(Digest::SHA512)

  class TestSHA2 < Test::Unit::TestCase

  def test_s_file
    Tempfile.create("test_digest_file") { |tmpfile|
      str = Data1
      tmpfile.print str
      tmpfile.close

      assert_equal "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed"\
                   "8086072ba1e7cc2358baeca134c825a7",
                   Digest::SHA2.file(tmpfile.path, 384).hexdigest
    }
  end

  end if defined?(Digest::SHA2)

  class TestRMD160 < Test::Unit::TestCase
    include TestDigest
    ALGO = Digest::RMD160
    DATA = {
      Data1 => "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc",
      Data2 => "12a053384a9c0c88e405a06c27dcf49ada62eb2b",
    }
  end if defined?(Digest::RMD160)

  class TestCRC32 < Test::Unit::TestCase
    include TestDigest
    ALGO = Digest::CRC32
    DATA = {
      Data1 => "352441c2",
      Data2 => "171a3f5f",
    }

    def test_digest_byte_order
      # CRC32("abc") = 0x352441C2; raw digest bytes must be big-endian (MSB first)
      assert_equal [0x35, 0x24, 0x41, 0xC2], Digest::CRC32.digest("abc").bytes
    end

    def test_digest_length
      assert_equal 4, Digest::CRC32.new.digest_length
    end

    def test_block_length
      assert_equal 8, Digest::CRC32.new.block_length
    end

    def test_empty_string
      assert_equal "00000000", Digest::CRC32.hexdigest("")
    end

    def test_single_null_byte
      assert_equal "d202ef8d", Digest::CRC32.hexdigest("\x00".b)
    end

    def test_high_bytes
      # Exercises the unsigned byte masking (& 0xFF) in the update loop
      assert_equal "08eaaf6d", Digest::CRC32.hexdigest("\xFF\xFE\xFD".b)
    end

    def test_all_byte_values
      # Exercises every entry in the lookup table
      assert_equal "29058c73", Digest::CRC32.hexdigest((0..255).map(&:chr).join.b)
    end

    def test_incremental_equals_one_shot
      inc = Digest::CRC32.new
      inc << "a" << "b" << "c"
      assert_equal "352441c2", inc.hexdigest
    end

    def test_clone_mid_stream_independence
      d = Digest::CRC32.new
      d << "ab"
      copy = d.clone
      d << "c"
      copy << "c"
      assert_equal d.hexdigest, copy.hexdigest
    end

    def test_reset
      d = Digest::CRC32.new
      d << "abc"
      d.reset
      d << "abc"
      assert_equal "352441c2", d.hexdigest
    end

    def test_digest_is_non_destructive
      d = Digest::CRC32.new
      d << "abc"
      assert_equal d.hexdigest, d.hexdigest
    end

    def test_digest_bang_resets_state
      d = Digest::CRC32.new
      d << "abc"
      d.hexdigest!
      assert_equal "00000000", d.hexdigest
    end

    def test_initialize_copy_into_frozen_raises
      dest = Digest::CRC32.allocate
      dest.freeze
      assert_raise(FrozenError) { dest.send(:initialize_copy, Digest::CRC32.new) }
    end
  end

  class TestBLAKE3 < Test::Unit::TestCase
    include TestDigest
    ALGO = Digest::BLAKE3
    DATA = {
      Data1 => "6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85",
      Data2 => "c19012cc2aaf0dc3d8e5c45a1b79114d2df42abb2a410bf54be09e891af06ff8",
    }

    # Input byte i has value (i % 251), matching the BLAKE3
    # test_vectors.json fixture.  The expected value is the first 32 bytes
    # (the default digest length) of each case's extended output hash.
    TEST_VECTORS = {
      0 => "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262",
      1 => "2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213",
      64 => "4eed7141ea4a5cd4b788606bd23f46e212af9cacebacdc7d1f4c6dc7f2511b98",
      65 => "de1e5fa0be70df6d2be8fffd0e99ceaa8eb6e8c93a63f2d8d1c30ecb6b263dee",
      1023 => "10108970eeda3eb932baac1428c7a2163b0e924c9a9e25b35bba72b28f70bd11",
      1024 => "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7",
      1025 => "d00278ae47eb27b34faecf67b4fe263f82d5412916c1ffd97c8cb7fb814b8444",
      2048 => "e776b6028c7cd22a4d0ba182a8bf62205d2ef576467e838ed6f2529b85fba24a",
      3072 => "b98cb0ff3623be03326b373de6b9095218513e64f1ee2edd2525c7ad1e5cffd2",
      4096 => "015094013f57a5277b59d8475c0501042c0b642e531b0a1c8f58d2163229e969",
      8192 => "aae792484c8efe4f19e2ca7d371d8c467ffb10748d8a5a1ae579948f718a2a63",
      16384 => "f875d6646de28985646f34ee13be9a576fd515f76b5b0a26bb324735041ddde4",
      102400 => "bc3e3d41a1146b069abffad3c0d44860cf664390afce4d9661f7902e7943e085",
    }

    # https://github.com/BLAKE3-team/BLAKE3/blob/93a431c78a52d7ccf0f366f106467f5070e6075e/test_vectors/src/lib.rs#L65-L73
    def paint_test_input(len)
      len.times.map { |i| (i % 251).chr }.join
    end

    def test_digest_length
      assert_equal 32, Digest::BLAKE3.new.digest_length
    end

    def test_block_length
      assert_equal 64, Digest::BLAKE3.new.block_length
    end

    def test_empty_string
      assert_equal "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262",
                   Digest::BLAKE3.hexdigest("")
    end

    def test_known_vectors
      # Exercises single-chunk, chunk-boundary and multi-chunk tree hashing
      # against the upstream BLAKE3 test vectors.
      TEST_VECTORS.each do |len, expected|
        assert_equal expected, Digest::BLAKE3.hexdigest(paint_test_input(len)),
                     "BLAKE3 of #{len}-byte test input"
      end
    end

    def test_incremental_equals_one_shot
      # Feed a multi-chunk input in awkward, unaligned pieces and compare
      # against the one-shot digest for the same bytes.
      input = paint_test_input(4097)
      inc = Digest::BLAKE3.new
      off = 0
      [1, 63, 64, 65, 900, 1024, 1080].each do |n|
        inc << input[off, n]
        off += n
      end
      inc << input[off..]
      assert_equal Digest::BLAKE3.hexdigest(input), inc.hexdigest
    end

    def test_clone_mid_stream_independence
      d = Digest::BLAKE3.new
      d << "ab"
      copy = d.clone
      d << "c"
      copy << "c"
      assert_equal d.hexdigest, copy.hexdigest
      assert_equal Digest::BLAKE3.hexdigest("abc"), copy.hexdigest
    end

    def test_reset
      d = Digest::BLAKE3.new
      d << "some other data"
      d.reset
      d << "abc"
      assert_equal Digest::BLAKE3.hexdigest("abc"), d.hexdigest
    end

    def test_digest_bang_resets_state
      d = Digest::BLAKE3.new
      d << "abc"
      d.hexdigest!
      assert_equal Digest::BLAKE3.hexdigest(""), d.hexdigest
    end

    def test_initialize_copy_into_frozen_raises
      dest = Digest::BLAKE3.allocate
      dest.freeze
      assert_raise(FrozenError) { dest.send(:initialize_copy, Digest::BLAKE3.new) }
    end
  end if defined?(Digest::BLAKE3)

  class TestBase < Test::Unit::TestCase
    def test_base
      bug3810 = '[ruby-core:32231]'
      assert_raise(NotImplementedError, bug3810) {Digest::Base.new}
    end
  end

  class TestInitCopy < Test::Unit::TestCase
    if defined?(Digest::MD5) and defined?(Digest::RMD160)
      def test_initialize_copy_md5_rmd160
        assert_separately(%w[-rdigest], <<-'end;')
          md5 = Digest::MD5.allocate
          rmd160 = Digest::RMD160.allocate
          assert_raise(TypeError) {md5.__send__(:initialize_copy, rmd160)}
        end;
      end
    end
  end

  class TestDigestParen < Test::Unit::TestCase
    def test_sha2
      assert_separately(%w[-rdigest], <<-'end;')
        assert_nothing_raised {
          Digest(:SHA256).new
          Digest(:SHA384).new
          Digest(:SHA512).new
        }
      end;
    end

    def test_no_lib
      assert_separately(%w[-rdigest], <<-'end;')
        class Digest::Nolib < Digest::Class
        end

        assert_nothing_raised {
          Digest(:Nolib).new
        }
      end;
    end

    def test_no_lib_no_def
      assert_separately(%w[-rdigest], <<-'end;')
        assert_raise(LoadError) {
          Digest(:Nodef).new
        }
      end;
    end

    def test_race
      assert_separately(['-rdigest', "-I#{File.dirname(__FILE__)}"], <<-"end;")
        assert_nothing_raised {
          t = Thread.start {
            sleep #{ EnvUtil.apply_timeout_scale(0.1) }
            Digest(:Foo).new
          }
          Digest(:Foo).new
          t.join
        }
      end;
    end

    def test_race_mixed
      assert_separately(['-rdigest', "-I#{File.dirname(__FILE__)}"], <<-"end;")
        assert_nothing_raised {
          t = Thread.start {
            sleep #{ EnvUtil.apply_timeout_scale(0.1) }
            Thread.current.report_on_exception = false
            Digest::Foo.new
          }
          Digest(:Foo).new
          begin
            t.join
          rescue NoMethodError, NameError
            # NoMethodError is highly likely; NameError is listed just in case
          end
        }
      end;
    end
  end
end
