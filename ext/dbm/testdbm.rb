require 'runit/testcase'
require 'runit/cui/testrunner'

if $".grep(/\bdbm.so\b/).empty?
  begin
    require './dbm'
  rescue LoadError
    require 'dbm'
  end
end

def uname_s
  require 'rbconfig'
  case Config::CONFIG['host_os']
  when 'cygwin'
    require 'Win32API'
    uname = Win32API.new('cygwin1', 'uname', 'P', 'I')
    utsname = ' ' * 100
    raise 'cannot get system name' if uname.call(utsname) == -1

    utsname.unpack('A20' * 5)[0]
  else
    Config::CONFIG['host_os']
  end
end

SYSTEM = uname_s

class TestDBM < RUNIT::TestCase
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
    GC.start
    File.delete *Dir.glob("tmptest_dbm*").to_a
    p Dir.glob("tmptest_dbm*") if $DEBUG
  end

  def check_size(expect, dbm=@dbm)
    assert_equals(expect, dbm.size)
    n = 0
    dbm.each { n+=1 }
    assert_equals(expect, n)
    if expect == 0
      assert_equals(true, dbm.empty?)
    else
      assert_equals(false, dbm.empty?)
    end
  end

  def test_version
    STDERR.print DBM::VERSION
  end

  def test_s_new_has_no_block
    # DBM.new ignore the block
    foo = true
    assert_instance_of(DBM, dbm = DBM.new("tmptest_dbm") { foo = false })
    assert_equals(foo, true)
    assert_nil(dbm.close)
  end
  def test_s_open_no_create
    assert_nil(dbm = DBM.open("tmptest_dbm", nil))
  ensure
    dbm.close if dbm
  end
  def test_s_open_with_block
    assert_equals(DBM.open("tmptest_dbm") { :foo }, :foo)
  end
  def test_s_open_lock
    fork() {
      assert_instance_of(DBM, dbm = DBM.open("tmptest_dbm", 0644))
      sleep 2
    }
    begin
      sleep 1
      assert_exception(Errno::EWOULDBLOCK, "NEVER MIND IF YOU USE Berkeley DB3") {
	begin
	  assert_instance_of(DBM, dbm2 = DBM.open("tmptest_dbm", 0644))
	rescue Errno::EAGAIN, Errno::EACCES, Errno::EINVAL
	  raise Errno::EWOULDBLOCK
	end
      }
    ensure
      Process.wait
    end
  end

=begin
  # Is it guaranteed on many OS?
  def test_s_open_lock_one_process
    # locking on one process
    assert_instance_of(DBM, dbm  = DBM.open("tmptest_dbm", 0644))
    assert_exception(Errno::EWOULDBLOCK) {
      begin
	DBM.open("tmptest_dbm", 0644)
      rescue Errno::EAGAIN
	raise Errno::EWOULDBLOCK
      end
    }
  end
=end

  def test_s_open_nolock
    # dbm 1.8.0 specific
    if not defined? DBM::NOLOCK
      return
    end

    fork() {
      assert_instance_of(DBM, dbm  = DBM.open("tmptest_dbm", 0644,
						DBM::NOLOCK))
      sleep 2
    }
    sleep 1
    begin
      dbm2 = nil
      assert_no_exception(Errno::EWOULDBLOCK, Errno::EAGAIN, Errno::EACCES) {
	assert_instance_of(DBM, dbm2 = DBM.open("tmptest_dbm", 0644))
      }
    ensure
      Process.wait
      dbm2.close if dbm2
    end

    p Dir.glob("tmptest_dbm*") if $DEBUG

    fork() {
      assert_instance_of(DBM, dbm  = DBM.open("tmptest_dbm", 0644))
      sleep 2
    }
    begin
      sleep 1
      dbm2 = nil
      assert_no_exception(Errno::EWOULDBLOCK, Errno::EAGAIN, Errno::EACCES) {
	# this test is failed on Cygwin98 (???)
	assert_instance_of(DBM, dbm2 = DBM.open("tmptest_dbm", 0644,
						   DBM::NOLOCK))
      }
    ensure
      Process.wait
      dbm2.close if dbm2
    end
  end

  def test_s_open_error
    assert_instance_of(DBM, dbm = DBM.open("tmptest_dbm", 0))
    assert_exception(Errno::EACCES, "NEVER MIND IF YOU USE Berkeley DB3") {
      DBM.open("tmptest_dbm", 0)
    }
    dbm.close
  end

  def test_close
    assert_instance_of(DBM, dbm = DBM.open("tmptest_dbm"))
    assert_nil(dbm.close)

    # closed DBM file
    assert_exception(DBMError) { dbm.close }
  end

  def test_aref
    assert_equals('bar', @dbm['foo'] = 'bar')
    assert_equals('bar', @dbm['foo'])

    assert_nil(@dbm['bar'])
  end

  def test_fetch
    assert_equals('bar', @dbm['foo']='bar')
    assert_equals('bar', @dbm.fetch('foo'))

    # key not found
    assert_exception(IndexError) {
      @dbm.fetch('bar')
    }

    # test for `ifnone' arg
    assert_equals('baz', @dbm.fetch('bar', 'baz'))

    # test for `ifnone' block
    assert_equals('foobar', @dbm.fetch('bar') {|key| 'foo' + key })
  end

  def test_aset
    num = 0
    2.times {|i|
      assert_equals('foo', @dbm['foo'] = 'foo')
      assert_equals('foo', @dbm['foo'])
      assert_equals('bar', @dbm['foo'] = 'bar')
      assert_equals('bar', @dbm['foo'])

      num += 1 if i == 0
      assert_equals(num, @dbm.size)

      # assign nil
      assert_equals('', @dbm['bar'] = '')
      assert_equals('', @dbm['bar'])

      num += 1 if i == 0
      assert_equals(num, @dbm.size)

      # empty string
      assert_equals('', @dbm[''] = '')
      assert_equals('', @dbm[''])

      num += 1 if i == 0
      assert_equals(num, @dbm.size)

      # Fixnum
      assert_equals('200', @dbm['100'] = '200')
      assert_equals('200', @dbm['100'])

      num += 1 if i == 0
      assert_equals(num, @dbm.size)

      # Big key and value
      assert_equals('y' * 100, @dbm['x' * 100] = 'y' * 100)
      assert_equals('y' * 100, @dbm['x' * 100])

      num += 1 if i == 0
      assert_equals(num, @dbm.size)
    }
  end

  def test_index
    assert_equals('bar', @dbm['foo'] = 'bar')
    assert_equals('foo', @dbm.index('bar'))
    assert_nil(@dbm['bar'])
  end

  def test_indexes
    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)
    @dbm[keys[0]], @dbm[keys[1]], @dbm[keys[2]] = values
    assert_equals(values.reverse, @dbm.indexes(*keys.reverse))
  end

  def test_values_at
    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)
    @dbm[keys[0]], @dbm[keys[1]], @dbm[keys[2]] = values
    assert_equals(values.reverse, @dbm.values_at(*keys.reverse))
  end

  def test_select_with_block
    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)
    @dbm[keys[0]], @dbm[keys[1]], @dbm[keys[2]] = values
    ret = @dbm.select {|k,v|
      assert_equals(k.upcase, v)
      k != "bar"
    }
    assert_equals([['baz', 'BAZ'], ['foo', 'FOO']],
		  ret.sort)
  end

  def test_length
    num = 10
    assert_equals(0, @dbm.size)
    num.times {|i|
      i = i.to_s
      @dbm[i] = i
    }
    assert_equals(num, @dbm.size)

    @dbm.shift

    assert_equals(num - 1, @dbm.size)
  end

  def test_empty?
    assert_equals(true, @dbm.empty?)
    @dbm['foo'] = 'FOO'
    assert_equals(false, @dbm.empty?)
  end

  def test_each_pair
    n = 0
    @dbm.each_pair { n += 1 }
    assert_equals(0, n)

    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)

    @dbm[keys[0]], @dbm[keys[1]], @dbm[keys[2]] = values

    n = 0
    ret = @dbm.each_pair {|key, val|
      assert_not_nil(i = keys.index(key))
      assert_equals(val, values[i])

      n += 1
    }
    assert_equals(keys.size, n)
    assert_equals(@dbm, ret)
  end

  def test_each_value
    n = 0
    @dbm.each_value { n += 1 }
    assert_equals(0, n)

    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)

    @dbm[keys[0]], @dbm[keys[1]], @dbm[keys[2]] = values

    n = 0
    ret = @dbm.each_value {|val|
      assert_not_nil(key = @dbm.index(val))
      assert_not_nil(i = keys.index(key))
      assert_equals(val, values[i])

      n += 1
    }
    assert_equals(keys.size, n)
    assert_equals(@dbm, ret)
  end

  def test_each_key
    n = 0
    @dbm.each_key { n += 1 }
    assert_equals(0, n)

    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)

    @dbm[keys[0]], @dbm[keys[1]], @dbm[keys[2]] = values

    n = 0
    ret = @dbm.each_key {|key|
      assert_not_nil(i = keys.index(key))
      assert_equals(@dbm[key], values[i])

      n += 1
    }
    assert_equals(keys.size, n)
    assert_equals(@dbm, ret)
  end

  def test_keys
    assert_equals([], @dbm.keys)

    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)

    @dbm[keys[0]], @dbm[keys[1]], @dbm[keys[2]] = values

    assert_equals(keys.sort, @dbm.keys.sort)
    assert_equals(values.sort, @dbm.values.sort)
  end

  def test_values
    test_keys
  end

  def test_shift
    assert_nil(@dbm.shift)
    assert_equals(0, @dbm.size)

    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)

    @dbm[keys[0]], @dbm[keys[1]], @dbm[keys[2]] = values

    ret_keys = []
    ret_values = []
    while ret = @dbm.shift
      ret_keys.push ret[0]
      ret_values.push ret[1]

      assert_equals(keys.size - ret_keys.size, @dbm.size)
    end

    assert_equals(keys.sort, ret_keys.sort)
    assert_equals(values.sort, ret_values.sort)
  end

  def test_delete
    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)
    key = keys[1]

    assert_nil(@dbm.delete(key))
    assert_equals(0, @dbm.size)

    @dbm[keys[0]], @dbm[keys[1]], @dbm[keys[2]] = values

    assert_equals('BAR', @dbm.delete(key))
    assert_nil(@dbm[key])
    assert_equals(2, @dbm.size)

    assert_nil(@dbm.delete(key))

    if /^CYGWIN_9/ !~ SYSTEM
      assert_exception(DBMError) {
	@dbm_rdonly.delete("foo")
      }

      assert_nil(@dbm_rdonly.delete("bar"))
    end
  end
  def test_delete_with_block
    key = 'no called block'
    @dbm[key] = 'foo'
    assert_equals('foo', @dbm.delete(key) {|k| k.replace 'called block'})
    assert_equals('no called block', key)
    assert_equals(0, @dbm.size)

    key = 'no called block'
    assert_equals(:blockval,
		  @dbm.delete(key) {|k| k.replace 'called block'; :blockval})
    assert_equals('called block', key)
    assert_equals(0, @dbm.size)
  end

  def test_delete_if
    v = "0"
    100.times {@dbm[v] = v; v = v.next}

    ret = @dbm.delete_if {|key, val| key.to_i < 50}
    assert_equals(@dbm, ret)
    check_size(50, @dbm)

    ret = @dbm.delete_if {|key, val| key.to_i >= 50}
    assert_equals(@dbm, ret)
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
    assert_equals(51, n)
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
    assert_equals(51, n)
    check_size(49, @dbm)
  end

  def test_reject
    v = "0"
    100.times {@dbm[v] = v; v = v.next}

    hash = @dbm.reject {|key, val| key.to_i < 50}
    assert_instance_of(Hash, hash)
    assert_equals(100, @dbm.size)

    assert_equals(50, hash.size)
    hash.each_pair {|key,val|
      assert_equals(false, key.to_i < 50)
      assert_equals(key, val)
    }

    hash = @dbm.reject {|key, val| key.to_i < 100}
    assert_instance_of(Hash, hash)
    assert_equals(true, hash.empty?)
  end

  def test_clear
    v = "1"
    100.times {v = v.next; @dbm[v] = v}

    assert_equals(@dbm, @dbm.clear)

    # validate DBM#size
    i = 0
    @dbm.each { i += 1 }
    assert_equals(@dbm.size, i)
    assert_equals(0, i)
  end

  def test_invert
    v = "0"
    100.times {@dbm[v] = v; v = v.next}

    hash = @dbm.invert
    assert_instance_of(Hash, hash)
    assert_equals(100, hash.size)
    hash.each_pair {|key, val|
      assert_equals(key.to_i, val.to_i)
    }
  end

  def test_update
    hash = {}
    v = "0"
    100.times {v = v.next; hash[v] = v}

    @dbm["101"] = "101"
    @dbm.update hash
    assert_equals(101, @dbm.size)
    @dbm.each_pair {|key, val|
      assert_equals(key.to_i, val.to_i)
    }
  end

  def test_replace
    hash = {}
    v = "0"
    100.times {v = v.next; hash[v] = v}

    @dbm["101"] = "101"
    @dbm.replace hash
    assert_equals(100, @dbm.size)
    @dbm.each_pair {|key, val|
      assert_equals(key.to_i, val.to_i)
    }
  end

  def test_haskey?
    assert_equals('bar', @dbm['foo']='bar')
    assert_equals(true,  @dbm.has_key?('foo'))
    assert_equals(false, @dbm.has_key?('bar'))
  end

  def test_has_value?
    assert_equals('bar', @dbm['foo']='bar')
    assert_equals(true,  @dbm.has_value?('bar'))
    assert_equals(false, @dbm.has_value?('foo'))
  end

  def test_to_a
    v = "0"
    100.times {v = v.next; @dbm[v] = v}

    ary = @dbm.to_a
    assert_instance_of(Array, ary)
    assert_equals(100, ary.size)
    ary.each {|key,val|
      assert_equals(key.to_i, val.to_i)
    }
  end

  def test_to_hash
    v = "0"
    100.times {v = v.next; @dbm[v] = v}

    hash = @dbm.to_hash
    assert_instance_of(Hash, hash)
    assert_equals(100, hash.size)
    hash.each {|key,val|
      assert_equals(key.to_i, val.to_i)
    }
  end
end

if $0 == __FILE__
  if ARGV.size == 0
    suite = RUNIT::TestSuite.new
    suite.add_test(TestDBM.suite)
  else
    suite = RUNIT::TestSuite.new
    ARGV.each do |testmethod|
      suite.add_test(TestDBM.new(testmethod))
    end
  end

  RUNIT::CUI::TestRunner.run(suite)
end
