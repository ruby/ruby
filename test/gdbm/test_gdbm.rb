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

    def test_open
      GDBM.open("#{TMPROOT}/a.dbm") {}
      v = GDBM.open("#{TMPROOT}/a.dbm", nil, GDBM::READER) {|d|
        assert_raises(GDBMError) { d["k"] = "v" }
        true
      }
      assert(v)
    end
  end
end
