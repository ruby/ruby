# frozen_string_literal: false
require "test/unit"
require "irb"
require "fileutils"

module TestIRB
  class TestInit < Test::Unit::TestCase
    def test_setup_with_argv_preserves_global_argv
      argv = ["foo", "bar"]
      with_argv(argv) do
        IRB.setup(eval("__FILE__"), argv: %w[-f])
        assert_equal argv, ARGV
      end
    end

    def test_setup_with_minimum_argv_does_not_change_dollar0
      orig = $0.dup
      IRB.setup(eval("__FILE__"), argv: %w[-f])
      assert_equal orig, $0
    end

    def test_rc_file
      backup_irbrc = ENV.delete("IRBRC") # This is for RVM...
      backup_home = ENV["HOME"]
      Dir.mktmpdir("test_irb_init_#{$$}") do |tmpdir|
        ENV["HOME"] = tmpdir

        IRB.conf[:RC_NAME_GENERATOR] = nil
        assert_equal(tmpdir+"/.irb#{IRB::IRBRC_EXT}", IRB.rc_file)
        assert_equal(tmpdir+"/.irb_history", IRB.rc_file("_history"))
        IRB.conf[:RC_NAME_GENERATOR] = nil
        FileUtils.touch(tmpdir+"/.irb#{IRB::IRBRC_EXT}")
        assert_equal(tmpdir+"/.irb#{IRB::IRBRC_EXT}", IRB.rc_file)
        assert_equal(tmpdir+"/.irb_history", IRB.rc_file("_history"))
      end
    ensure
      ENV["HOME"] = backup_home
      ENV["IRBRC"] = backup_irbrc
    end

    def test_rc_file_in_subdir
      backup_irbrc = ENV.delete("IRBRC") # This is for RVM...
      backup_home = ENV["HOME"]
      Dir.mktmpdir("test_irb_init_#{$$}") do |tmpdir|
        ENV["HOME"] = tmpdir

        FileUtils.mkdir_p("#{tmpdir}/mydir")
        Dir.chdir("#{tmpdir}/mydir") do
          IRB.conf[:RC_NAME_GENERATOR] = nil
          assert_equal(tmpdir+"/.irb#{IRB::IRBRC_EXT}", IRB.rc_file)
          assert_equal(tmpdir+"/.irb_history", IRB.rc_file("_history"))
          IRB.conf[:RC_NAME_GENERATOR] = nil
          FileUtils.touch(tmpdir+"/.irb#{IRB::IRBRC_EXT}")
          assert_equal(tmpdir+"/.irb#{IRB::IRBRC_EXT}", IRB.rc_file)
          assert_equal(tmpdir+"/.irb_history", IRB.rc_file("_history"))
        end
      end
    ensure
      ENV["HOME"] = backup_home
      ENV["IRBRC"] = backup_irbrc
    end

    private

    def with_argv(argv)
      orig = ARGV.dup
      ARGV.replace(argv)
      yield
    ensure
      ARGV.replace(orig)
    end
  end
end
