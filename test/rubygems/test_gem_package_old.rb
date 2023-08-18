# frozen_string_literal: true

require_relative "helper"

unless Gem.java_platform? # jruby can't require the simple_gem file
  require "rubygems/simple_gem"

  class TestGemPackageOld < Gem::TestCase
    def setup
      super

      File.open "old_format.gem", "wb" do |io|
        io.write SIMPLE_GEM
      end

      @package = Gem::Package::Old.new "old_format.gem"
      @destination = File.join @tempdir, "extract"

      FileUtils.mkdir_p @destination
    end

    def test_contents
      assert_equal %w[lib/foo.rb lib/test.rb lib/test/wow.rb], @package.contents
    end

    def test_contents_security_policy
      pend "openssl is missing" unless Gem::HAVE_OPENSSL

      @package.security_policy = Gem::Security::AlmostNoSecurity

      assert_raise Gem::Security::Exception do
        @package.contents
      end
    end

    def test_extract_files
      @package.extract_files @destination

      extracted = File.join @destination, "lib/foo.rb"
      assert_path_exist extracted

      mask = 0100644 & (~File.umask)

      assert_equal mask, File.stat(extracted).mode unless win_platform?
    end

    def test_extract_files_security_policy
      pend "openssl is missing" unless Gem::HAVE_OPENSSL

      @package.security_policy = Gem::Security::AlmostNoSecurity

      assert_raise Gem::Security::Exception do
        @package.extract_files @destination
      end
    end

    def test_spec
      assert_equal "testing", @package.spec.name
    end

    def test_spec_security_policy
      pend "openssl is missing" unless Gem::HAVE_OPENSSL

      @package.security_policy = Gem::Security::AlmostNoSecurity

      assert_raise Gem::Security::Exception do
        @package.spec
      end
    end

    def test_verify
      pend "openssl is missing" unless Gem::HAVE_OPENSSL

      assert @package.verify

      @package.security_policy = Gem::Security::NoSecurity

      assert @package.verify

      @package.security_policy = Gem::Security::AlmostNoSecurity

      e = assert_raise Gem::Security::Exception do
        @package.verify
      end

      assert_equal "old format gems do not contain signatures " +
                   "and cannot be verified",
                   e.message
    end
  end
end
