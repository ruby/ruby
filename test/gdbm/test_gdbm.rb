require 'test/unit/testsuite'
require 'test/unit/testcase'

begin
  require 'gdbm'
rescue LoadError
end

if defined? GDBM
  require 'tmpdir'
  require 'fileutils'

  class TestGDBM < Test::Unit::TestCase
    TMPROOT = "#{Dir.tmpdir}/ruby-gdbm.#{$$}"

    def setup
      Dir.mkdir TMPROOT
    end

    def teardown
      FileUtils.rm_rf TMPROOT if File.directory?(TMPROOT)
    end

    def test_reader_open
      GDBM.open("#{TMPROOT}/a.dbm") {}
      v = GDBM.open("#{TMPROOT}/a.dbm", nil, GDBM::READER) {|d|
        assert_raises(GDBMError) { d["k"] = "v" }
        true
      }
      assert(v)
    end

    def test_newdb_open
      GDBM.open("#{TMPROOT}/a.dbm") {|dbm|
        dbm["k"] = "v"
      } 
      v = GDBM.open("#{TMPROOT}/a.dbm", nil, GDBM::NEWDB) {|d|
        assert_equal(0, d.length)
        assert_nil(d["k"])
        true
      }
      assert(v)
    end

    def test_freeze
      GDBM.open("#{TMPROOT}/a.dbm") {|d|
        d.freeze
        assert_raises(TypeError) { d["k"] = "v" }
      }
    end
  end
end
