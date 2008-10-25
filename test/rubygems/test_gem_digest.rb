#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require "rubygems/digest/md5"
require "rubygems/digest/sha1"
require "rubygems/digest/sha2"

class TestRubygemsGemDigest < RubyGemTestCase

  def test_sha256_hex_digest_works
    digester = Gem::SHA256.new
    assert_equal "b5d4045c3f466fa91fe2cc6abe79232a1a57cdf104f7a26e716e0a1e2789df78", digester.hexdigest("ABC")
  end

  def test_sha256_digest_works
    digester = Gem::SHA256.new
    assert_equal "\265\324\004\\?Fo\251\037\342\314j\276y#*\032W\315\361\004\367\242nqn\n\036'\211\337x",
      digester.digest("ABC")
  end

  def test_sha1_hex_digest_works
    digester = Gem::SHA1.new
    assert_equal "3c01bdbb26f358bab27f267924aa2c9a03fcfdb8", digester.hexdigest("ABC")
  end

  def test_sha1_digest_works
    digester = Gem::SHA1.new
    assert_equal "<\001\275\273&\363X\272\262\177&y$\252,\232\003\374\375\270", digester.digest("ABC")
  end

  def test_md5_hex_digest_works
    digester = Gem::MD5.new
    assert_equal "902fbdd2b1df0c4f70b4a5d23525e932", digester.hexdigest("ABC")
  end

  def test_md5_digest_works
    digester = Gem::MD5.new
    assert_equal "\220/\275\322\261\337\fOp\264\245\3225%\3512", digester.digest("ABC")
  end

end

