require 'test/unit/testsuite'
require 'test/unit/testcase'

begin
  require 'dbm'
rescue LoadError
end

if defined? DBM
  require 'tmpdir'
  require 'fileutils'

  class TestDBM < Test::Unit::TestCase
    TMPROOT = "#{Dir.tmpdir}/ruby-dbm.#{$$}"

    def setup
      Dir.mkdir TMPROOT
    end

    def teardown
      FileUtils.rm_rf TMPROOT if File.directory?(TMPROOT)
    end

    def test_reader_open
      DBM.open("#{TMPROOT}/a") {}
      v = DBM.open("#{TMPROOT}/a", nil, DBM::READER) {|d|
        # Errno::EPERM is raised on Solaris which use ndbm.
        # DBMError is raised on Debian which use gdbm. 
        assert_raises(Errno::EPERM, DBMError) { d["k"] = "v" }
        true
      }
      assert(v)
    end

    def test_newdb_open
      DBM.open("#{TMPROOT}/a") {|dbm|
        dbm["k"] = "v"
      }
      v = DBM.open("#{TMPROOT}/a", nil, DBM::NEWDB) {|d|
        assert_equal(0, d.length)
        assert_nil(d["k"])
        true
      }
      assert(v)
    end

    def test_freeze
      DBM.open("#{TMPROOT}/a") {|d|
        d.freeze
        assert_raises(TypeError) { d["k"] = "v" }
      }
    end
  end
end
