# frozen_string_literal: false
require 'test/unit'
require 'tmpdir'
require 'rbconfig'

module Bug
  module Win32
    class TestDln < Test::Unit::TestCase
      def test_check_imported
        bug = '[Bug #6303]'
        assert_in_out_err(['-r-test-/win32/dln', '-eexit'], '', [], [], bug, timeout: 10)
      end

      def test_nonascii_load
        bug9699 = '[ruby-core:61845] [Bug #9699]'
        so = "-test-/dln/empty." + RbConfig::CONFIG["DLEXT"]
        so = $:.find {|d| d = ::File.join(d, so); break d if ::File.exist?(d)}
        assert_not_nil(so)
        Dir.mkdir(dir = ::File.join(testdir = Dir.mktmpdir("test"), "\u{30c6 30b9 30c8}"))
        ::File.copy_stream(so, ::File.join(dir, ::File.basename(so)))
        assert_separately(['-', bug9699, testdir, ::File.basename(so)], <<-'end;')
          bug, dir, so = *ARGV
          assert_nothing_raised(LoadError, bug) do
            require ::File.join(dir, "\u{30c6 30b9 30c8}", so)
          end
        end;
      ensure
        ::File.unlink(::File.join(dir, ::File.basename(so))) rescue nil
        Dir.rmdir(dir) rescue nil
        Dir.rmdir(testdir) rescue nil
      end

    end
  end
end if /mswin|mingw/ =~ RUBY_PLATFORM
