#!/usr/bin/env ruby
#
# $RoughId: test.rb,v 1.4 2001/07/13 15:38:27 knu Exp $
# $Id$

require 'test/unit'

require 'digest/md5'
require 'digest/rmd160'
require 'digest/sha1'
require 'digest/sha2'
include Digest

class TestDigest < Test::Unit::TestCase
  ALGOS = [
    MD5,
    SHA1,
    SHA256,
    SHA384,
    SHA512,
    RMD160
  ]

  DATA = {
    "abc" => {
      MD5 => "900150983cd24fb0d6963f7d28e17f72",
      SHA1 => "a9993e364706816aba3e25717850c26c9cd0d89d",
      SHA256 => "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      SHA384 => "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7",
      SHA512 => "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
      RMD160 => "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc"
    },

    "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq" => {
      MD5 => "8215ef0796a20bcaaae116d3876c664a",
      SHA1 => "84983e441c3bd26ebaae4aa1f95129e5e54670f1",
      SHA256 => "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
      SHA384 => "3391fdddfc8dc7393707a65b1b4709397cf8b1d162af05abfe8f450de5f36bc6b0455a8520bc4e6f5fe95b1fe3c8452b",
      SHA512 => "204a8fc6dda82f0a0ced7beb8e08a41657c16ef468b228a8279be331a703c33596fd15c13b1b07f9aa1d3bea57789ca031ad85c7a71dd70354ec631238ca3445",
      RMD160 => "12a053384a9c0c88e405a06c27dcf49ada62eb2b"
    }
  }

  def test_s_hexdigest
    ALGOS.each do |algo|
      DATA.each do |str, table|
	assert_equal(table[algo], algo.hexdigest(str))
      end
    end
  end

  def test_s_digest
    ALGOS.each do |algo|
      DATA.each do |str, table|
	assert_equal([table[algo]].pack("H*"), algo.digest(str))
      end
    end
  end

  def test_update
    # This test is also for digest() and hexdigest()

    str = "ABC"

    ALGOS.each do |algo|
      md = algo.new
      md.update str
      assert_equal(algo.hexdigest(str), md.hexdigest)
      assert_equal(algo.digest(str), md.digest)
    end
  end

  def test_eq
    # This test is also for clone()

    ALGOS.each do |algo|
      md1 = algo.new("ABC")

      assert_equal(md1, md1.clone)

      md2 = algo.new
      md2 << "A"

      assert(md1 != md2)

      md2 << "BC"

      assert_equal(md1, md2)
    end
  end
end
