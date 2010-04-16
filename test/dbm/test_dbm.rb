require 'test/unit'

begin
  require 'dbm'
rescue LoadError
end

if defined? DBM
  require 'tmpdir'
  require 'fileutils'

  class TestDBM < Test::Unit::TestCase
    def TestDBM.uname_s
      require 'rbconfig'
      case Config::CONFIG['target_os']
      when 'cygwin'
        require 'Win32API'
        uname = Win32API.new('cygwin1', 'uname', 'P', 'I')
        utsname = ' ' * 100
        raise 'cannot get system name' if uname.call(utsname) == -1

        utsname.unpack('A20' * 5)[0]
      else
        Config::CONFIG['target_os']
      end
    end
    SYSTEM = uname_s

    def setup
      @path = "tmptest_dbm_"
      assert_instance_of(DBM, @dbm = DBM.new(@path))

      # prepare to make readonly DBM file
      DBM.open("tmptest_dbm_rdonly") {|dbm|
        dbm['foo'] = 'FOO'
      }

      File.chmod(0400, *Dir.glob("tmptest_dbm_rdonly.*"))

      assert_instance_of(DBM, @dbm_rdonly = DBM.new("tmptest_dbm_rdonly", nil))
    end
    def teardown
      assert_nil(@dbm.close)
      assert_nil(@dbm_rdonly.close)
      ObjectSpace.each_object(DBM) do |obj|
        obj.close unless obj.closed?
      end
      File.delete *Dir.glob("tmptest_dbm*").to_a
      p Dir.glob("tmptest_dbm*") if $DEBUG
    end

    def check_size(expect, dbm=@dbm)
      assert_equal(expect, dbm.size)
      n = 0
      dbm.each { n+=1 }
      assert_equal(expect, n)
      if expect == 0
        assert_equal(true, dbm.empty?)
      else
        assert_equal(false, dbm.empty?)
      end
    end

    def have_fork?
      begin
        fork{}
        true
      rescue NotImplementedError
        false
      end
    end

    def test_s_new_has_no_block
      # DBM.new ignore the block
      foo = true
      assert_instance_of(DBM, dbm = DBM.new("tmptest_dbm") { foo = false })
      assert_equal(foo, true)
      assert_nil(dbm.close)
    end
    def test_s_open_no_create
      assert_nil(dbm = DBM.open("tmptest_dbm", nil))
    ensure
      dbm.close if dbm
    end
    def test_s_open_with_block
      assert_equal(DBM.open("tmptest_dbm") { :foo }, :foo)
    end

    def test_close
      assert_instance_of(DBM, dbm = DBM.open("tmptest_dbm"))
      assert_nil(dbm.close)

      # closed DBM file
      assert_raise(DBMError) { dbm.close }
    end

    def test_aref
      assert_equal('bar', @dbm['foo'] = 'bar')
      assert_equal('bar', @dbm['foo'])

      assert_nil(@dbm['bar'])
    end

    def test_fetch
      assert_equal('bar', @dbm['foo']='bar')
      assert_equal('bar', @dbm.fetch('foo'))

      # key not found
      assert_raise(IndexError) {
        @dbm.fetch('bar')
      }

      # test for `ifnone' arg
      assert_equal('baz', @dbm.fetch('bar', 'baz'))

      # test for `ifnone' block
      assert_equal('foobar', @dbm.fetch('bar') {|key| 'foo' + key })
    end

    def test_aset
      num = 0
      2.times {|i|
        assert_equal('foo', @dbm['foo'] = 'foo')
        assert_equal('foo', @dbm['foo'])
        assert_equal('bar', @dbm['foo'] = 'bar')
        assert_equal('bar', @dbm['foo'])

        num += 1 if i == 0
        assert_equal(num, @dbm.size)

        # assign nil
        assert_equal('', @dbm['bar'] = '')
        assert_equal('', @dbm['bar'])

        num += 1 if i == 0
        assert_equal(num, @dbm.size)

        # empty string
        assert_equal('', @dbm[''] = '')
        assert_equal('', @dbm[''])

        num += 1 if i == 0
        assert_equal(num, @dbm.size)

        # Fixnum
        assert_equal('200', @dbm['100'] = '200')
        assert_equal('200', @dbm['100'])

        num += 1 if i == 0
        assert_equal(num, @dbm.size)

        # Big key and value
        assert_equal('y' * 100, @dbm['x' * 100] = 'y' * 100)
        assert_equal('y' * 100, @dbm['x' * 100])

        num += 1 if i == 0
        assert_equal(num, @dbm.size)
      }
    end

    def test_key
      assert_equal('bar', @dbm['foo'] = 'bar')
      assert_equal('foo', @dbm.key('bar'))
      assert_nil(@dbm['bar'])
    end

    def test_values_at
      keys = %w(foo bar baz)
      values = %w(FOO BAR BAZ)
      @dbm[keys[0]], @dbm[keys[1]], @dbm[keys[2]] = values
      assert_equal(values.reverse, @dbm.values_at(*keys.reverse))
    end

    def test_select_with_block
      keys = %w(foo bar baz)
      values = %w(FOO BAR BAZ)
      @dbm[keys[0]], @dbm[keys[1]], @dbm[keys[2]] = values
      ret = @dbm.select {|k,v|
        assert_equal(k.upcase, v)
        k != "bar"
      }
      assert_equal([['baz', 'BAZ'], ['foo', 'FOO']],
                    ret.sort)
    end

    def test_length
      num = 10
      assert_equal(0, @dbm.size)
      num.times {|i|
        i = i.to_s
        @dbm[i] = i
      }
      assert_equal(num, @dbm.size)

      @dbm.shift

      assert_equal(num - 1, @dbm.size)
    end

    def test_empty?
      assert_equal(true, @dbm.empty?)
      @dbm['foo'] = 'FOO'
      assert_equal(false, @dbm.empty?)
    end

    def test_each_pair
      n = 0
      @dbm.each_pair { n += 1 }
      assert_equal(0, n)

      keys = %w(foo bar baz)
      values = %w(FOO BAR BAZ)

      @dbm[keys[0]], @dbm[keys[1]], @dbm[keys[2]] = values

      n = 0
      ret = @dbm.each_pair {|key, val|
        assert_not_nil(i = keys.index(key))
        assert_equal(val, values[i])

        n += 1
      }
      assert_equal(keys.size, n)
      assert_equal(@dbm, ret)
    end

    def test_each_value
      n = 0
      @dbm.each_value { n += 1 }
      assert_equal(0, n)

      keys = %w(foo bar baz)
      values = %w(FOO BAR BAZ)

      @dbm[keys[0]], @dbm[keys[1]], @dbm[keys[2]] = values

      n = 0
      ret = @dbm.each_value {|val|
        assert_not_nil(key = @dbm.key(val))
        assert_not_nil(i = keys.index(key))
        assert_equal(val, values[i])

        n += 1
      }
      assert_equal(keys.size, n)
      assert_equal(@dbm, ret)
    end

    def test_each_key
      n = 0
      @dbm.each_key { n += 1 }
      assert_equal(0, n)

      keys = %w(foo bar baz)
      values = %w(FOO BAR BAZ)

      @dbm[keys[0]], @dbm[keys[1]], @dbm[keys[2]] = values

      n = 0
      ret = @dbm.each_key {|key|
        assert_not_nil(i = keys.index(key))
        assert_equal(@dbm[key], values[i])

        n += 1
      }
      assert_equal(keys.size, n)
      assert_equal(@dbm, ret)
    end

    def test_keys
      assert_equal([], @dbm.keys)

      keys = %w(foo bar baz)
      values = %w(FOO BAR BAZ)

      @dbm[keys[0]], @dbm[keys[1]], @dbm[keys[2]] = values

      assert_equal(keys.sort, @dbm.keys.sort)
      assert_equal(values.sort, @dbm.values.sort)
    end

    def test_values
      test_keys
    end

    def test_shift
      assert_nil(@dbm.shift)
      assert_equal(0, @dbm.size)

      keys = %w(foo bar baz)
      values = %w(FOO BAR BAZ)

      @dbm[keys[0]], @dbm[keys[1]], @dbm[keys[2]] = values

      ret_keys = []
      ret_values = []
      while ret = @dbm.shift
        ret_keys.push ret[0]
        ret_values.push ret[1]

        assert_equal(keys.size - ret_keys.size, @dbm.size)
      end

      assert_equal(keys.sort, ret_keys.sort)
      assert_equal(values.sort, ret_values.sort)
    end

    def test_delete
      keys = %w(foo bar baz)
      values = %w(FOO BAR BAZ)
      key = keys[1]

      assert_nil(@dbm.delete(key))
      assert_equal(0, @dbm.size)

      @dbm[keys[0]], @dbm[keys[1]], @dbm[keys[2]] = values

      assert_equal('BAR', @dbm.delete(key))
      assert_nil(@dbm[key])
      assert_equal(2, @dbm.size)

      assert_nil(@dbm.delete(key))

      if /^CYGWIN_9/ !~ SYSTEM
        assert_raise(DBMError) {
          @dbm_rdonly.delete("foo")
        }

        assert_nil(@dbm_rdonly.delete("bar"))
      end
    end
    def test_delete_with_block
      key = 'no called block'
      @dbm[key] = 'foo'
      assert_equal('foo', @dbm.delete(key) {|k| k.replace 'called block'})
      assert_equal('no called block', key)
      assert_equal(0, @dbm.size)

      key = 'no called block'
      assert_equal(:blockval,
                    @dbm.delete(key) {|k| k.replace 'called block'; :blockval})
      assert_equal('called block', key)
      assert_equal(0, @dbm.size)
    end

    def test_delete_if
      v = "0"
      100.times {@dbm[v] = v; v = v.next}

      ret = @dbm.delete_if {|key, val| key.to_i < 50}
      assert_equal(@dbm, ret)
      check_size(50, @dbm)

      ret = @dbm.delete_if {|key, val| key.to_i >= 50}
      assert_equal(@dbm, ret)
      check_size(0, @dbm)

      # break
      v = "0"
      100.times {@dbm[v] = v; v = v.next}
      check_size(100, @dbm)
      n = 0;
      @dbm.delete_if {|key, val|
        break if n > 50
        n+=1
        true
      }
      assert_equal(51, n)
      check_size(49, @dbm)

      @dbm.clear

      # raise
      v = "0"
      100.times {@dbm[v] = v; v = v.next}
      check_size(100, @dbm)
      n = 0;
      begin
        @dbm.delete_if {|key, val|
          raise "runtime error" if n > 50
          n+=1
          true
        }
      rescue
      end
      assert_equal(51, n)
      check_size(49, @dbm)
    end

    def test_reject
      v = "0"
      100.times {@dbm[v] = v; v = v.next}

      hash = @dbm.reject {|key, val| key.to_i < 50}
      assert_instance_of(Hash, hash)
      assert_equal(100, @dbm.size)

      assert_equal(50, hash.size)
      hash.each_pair {|key,val|
        assert_equal(false, key.to_i < 50)
        assert_equal(key, val)
      }

      hash = @dbm.reject {|key, val| key.to_i < 100}
      assert_instance_of(Hash, hash)
      assert_equal(true, hash.empty?)
    end

    def test_clear
      v = "1"
      100.times {v = v.next; @dbm[v] = v}

      assert_equal(@dbm, @dbm.clear)

      # validate DBM#size
      i = 0
      @dbm.each { i += 1 }
      assert_equal(@dbm.size, i)
      assert_equal(0, i)
    end

    def test_invert
      v = "0"
      100.times {@dbm[v] = v; v = v.next}

      hash = @dbm.invert
      assert_instance_of(Hash, hash)
      assert_equal(100, hash.size)
      hash.each_pair {|key, val|
        assert_equal(key.to_i, val.to_i)
      }
    end

    def test_update
      hash = {}
      v = "0"
      100.times {v = v.next; hash[v] = v}

      @dbm["101"] = "101"
      @dbm.update hash
      assert_equal(101, @dbm.size)
      @dbm.each_pair {|key, val|
        assert_equal(key.to_i, val.to_i)
      }
    end

    def test_replace
      hash = {}
      v = "0"
      100.times {v = v.next; hash[v] = v}

      @dbm["101"] = "101"
      @dbm.replace hash
      assert_equal(100, @dbm.size)
      @dbm.each_pair {|key, val|
        assert_equal(key.to_i, val.to_i)
      }
    end

    def test_haskey?
      assert_equal('bar', @dbm['foo']='bar')
      assert_equal(true,  @dbm.has_key?('foo'))
      assert_equal(false, @dbm.has_key?('bar'))
    end

    def test_has_value?
      assert_equal('bar', @dbm['foo']='bar')
      assert_equal(true,  @dbm.has_value?('bar'))
      assert_equal(false, @dbm.has_value?('foo'))
    end

    def test_to_a
      v = "0"
      100.times {v = v.next; @dbm[v] = v}

      ary = @dbm.to_a
      assert_instance_of(Array, ary)
      assert_equal(100, ary.size)
      ary.each {|key,val|
        assert_equal(key.to_i, val.to_i)
      }
    end

    def test_to_hash
      v = "0"
      100.times {v = v.next; @dbm[v] = v}

      hash = @dbm.to_hash
      assert_instance_of(Hash, hash)
      assert_equal(100, hash.size)
      hash.each {|key,val|
        assert_equal(key.to_i, val.to_i)
      }
    end
  end

  class TestDBM2 < Test::Unit::TestCase
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
