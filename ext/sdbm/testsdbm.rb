require 'runit/testcase'
require 'runit/cui/testrunner'

if $".grep(/\bsdbm.so\b/).empty?
  begin
    require './sdbm'
  rescue LoadError
    require 'sdbm'
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

class TestSDBM < RUNIT::TestCase
  def setup
    @path = "tmptest_sdbm_"
    assert_instance_of(SDBM, @sdbm = SDBM.new(@path))
  end
  def teardown
    assert_nil(@sdbm.close)
    GC.start
    File.delete *Dir.glob("tmptest_sdbm*").to_a
    p Dir.glob("tmptest_sdbm*") if $DEBUG
  end

  def check_size(expect, sdbm=@sdbm)
    assert_equals(expect, sdbm.size)
    n = 0
    sdbm.each { n+=1 }
    assert_equals(expect, n)
    if expect == 0
      assert_equals(true, sdbm.empty?)
    else
      assert_equals(false, sdbm.empty?)
    end
  end

  def test_version
    assert(! SDBM.const_defined?(:VERSION))
  end

  def test_s_new_has_no_block
    # SDBM.new ignore the block
    foo = true
    assert_instance_of(SDBM, sdbm = SDBM.new("tmptest_sdbm") { foo = false })
    assert_equals(foo, true)
    assert_nil(sdbm.close)
  end
  def test_s_open_no_create
    assert_nil(sdbm = SDBM.open("tmptest_sdbm", nil))
  ensure
    sdbm.close if sdbm
  end
  def test_s_open_with_block
    assert_equals(SDBM.open("tmptest_sdbm") { :foo }, :foo)
  end
=begin
  # Is it guaranteed on many OS?
  def test_s_open_lock_one_process
    # locking on one process
    assert_instance_of(SDBM, sdbm  = SDBM.open("tmptest_sdbm", 0644))
    assert_exception(Errno::EWOULDBLOCK) {
      begin
	SDBM.open("tmptest_sdbm", 0644)
      rescue Errno::EAGAIN
	raise Errno::EWOULDBLOCK
      end
    }
  end
=end

  def test_s_open_nolock
    # sdbm 1.8.0 specific
    if not defined? SDBM::NOLOCK
      return
    end

    fork() {
      assert_instance_of(SDBM, sdbm  = SDBM.open("tmptest_sdbm", 0644,
						SDBM::NOLOCK))
      sleep 2
    }
    sleep 1
    begin
      sdbm2 = nil
      assert_no_exception(Errno::EWOULDBLOCK, Errno::EAGAIN, Errno::EACCES) {
	assert_instance_of(SDBM, sdbm2 = SDBM.open("tmptest_sdbm", 0644))
      }
    ensure
      Process.wait
      sdbm2.close if sdbm2
    end

    p Dir.glob("tmptest_sdbm*") if $DEBUG

    fork() {
      assert_instance_of(SDBM, sdbm  = SDBM.open("tmptest_sdbm", 0644))
      sleep 2
    }
    begin
      sleep 1
      sdbm2 = nil
      assert_no_exception(Errno::EWOULDBLOCK, Errno::EAGAIN, Errno::EACCES) {
	# this test is failed on Cygwin98 (???)
	assert_instance_of(SDBM, sdbm2 = SDBM.open("tmptest_sdbm", 0644,
						   SDBM::NOLOCK))
      }
    ensure
      Process.wait
      sdbm2.close if sdbm2
    end
  end

  def test_s_open_error
    assert_instance_of(SDBM, sdbm = SDBM.open("tmptest_sdbm", 0))
    assert_exception(Errno::EACCES) {
      SDBM.open("tmptest_sdbm", 0)
    }
    sdbm.close
  end

  def test_close
    assert_instance_of(SDBM, sdbm = SDBM.open("tmptest_sdbm"))
    assert_nil(sdbm.close)

    # closed SDBM file
    assert_exception(SDBMError) { sdbm.close }
  end

  def test_aref
    assert_equals('bar', @sdbm['foo'] = 'bar')
    assert_equals('bar', @sdbm['foo'])

    assert_nil(@sdbm['bar'])
  end

  def test_fetch
    assert_equals('bar', @sdbm['foo']='bar')
    assert_equals('bar', @sdbm.fetch('foo'))

    # key not found
    assert_exception(IndexError) {
      @sdbm.fetch('bar')
    }

    # test for `ifnone' arg
    assert_equals('baz', @sdbm.fetch('bar', 'baz'))

    # test for `ifnone' block
    assert_equals('foobar', @sdbm.fetch('bar') {|key| 'foo' + key })
  end

  def test_aset
    num = 0
    2.times {|i|
      assert_equals('foo', @sdbm['foo'] = 'foo')
      assert_equals('foo', @sdbm['foo'])
      assert_equals('bar', @sdbm['foo'] = 'bar')
      assert_equals('bar', @sdbm['foo'])

      num += 1 if i == 0
      assert_equals(num, @sdbm.size)

      # assign nil
      assert_equals('', @sdbm['bar'] = '')
      assert_equals('', @sdbm['bar'])

      num += 1 if i == 0
      assert_equals(num, @sdbm.size)

      # empty string
      assert_equals('', @sdbm[''] = '')
      assert_equals('', @sdbm[''])

      num += 1 if i == 0
      assert_equals(num, @sdbm.size)

      # Fixnum
      assert_equals('200', @sdbm['100'] = '200')
      assert_equals('200', @sdbm['100'])

      num += 1 if i == 0
      assert_equals(num, @sdbm.size)

      # Big key and value
      assert_equals('y' * 100, @sdbm['x' * 100] = 'y' * 100)
      assert_equals('y' * 100, @sdbm['x' * 100])

      num += 1 if i == 0
      assert_equals(num, @sdbm.size)
    }
  end

  def test_index
    assert_equals('bar', @sdbm['foo'] = 'bar')
    assert_equals('foo', @sdbm.index('bar'))
    assert_nil(@sdbm['bar'])
  end

  def test_indexes
    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)
    @sdbm[keys[0]], @sdbm[keys[1]], @sdbm[keys[2]] = values
    assert_equals(values.reverse, @sdbm.indexes(*keys.reverse))
  end

  def test_values_at
    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)
    @sdbm[keys[0]], @sdbm[keys[1]], @sdbm[keys[2]] = values
    assert_equals(values.reverse, @sdbm.values_at(*keys.reverse))
  end

  def test_select_with_block
    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)
    @sdbm[keys[0]], @sdbm[keys[1]], @sdbm[keys[2]] = values
    ret = @sdbm.select {|k,v|
      assert_equals(k.upcase, v)
      k != "bar"
    }
    assert_equals([['baz', 'BAZ'], ['foo', 'FOO']],
		  ret.sort)
  end

  def test_length
    num = 10
    assert_equals(0, @sdbm.size)
    num.times {|i|
      i = i.to_s
      @sdbm[i] = i
    }
    assert_equals(num, @sdbm.size)

    @sdbm.shift

    assert_equals(num - 1, @sdbm.size)
  end

  def test_empty?
    assert_equals(true, @sdbm.empty?)
    @sdbm['foo'] = 'FOO'
    assert_equals(false, @sdbm.empty?)
  end

  def test_each_pair
    n = 0
    @sdbm.each_pair { n += 1 }
    assert_equals(0, n)

    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)

    @sdbm[keys[0]], @sdbm[keys[1]], @sdbm[keys[2]] = values

    n = 0
    ret = @sdbm.each_pair {|key, val|
      assert_not_nil(i = keys.index(key))
      assert_equals(val, values[i])

      n += 1
    }
    assert_equals(keys.size, n)
    assert_equals(@sdbm, ret)
  end

  def test_each_value
    n = 0
    @sdbm.each_value { n += 1 }
    assert_equals(0, n)

    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)

    @sdbm[keys[0]], @sdbm[keys[1]], @sdbm[keys[2]] = values

    n = 0
    ret = @sdbm.each_value {|val|
      assert_not_nil(key = @sdbm.index(val))
      assert_not_nil(i = keys.index(key))
      assert_equals(val, values[i])

      n += 1
    }
    assert_equals(keys.size, n)
    assert_equals(@sdbm, ret)
  end

  def test_each_key
    n = 0
    @sdbm.each_key { n += 1 }
    assert_equals(0, n)

    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)

    @sdbm[keys[0]], @sdbm[keys[1]], @sdbm[keys[2]] = values

    n = 0
    ret = @sdbm.each_key {|key|
      assert_not_nil(i = keys.index(key))
      assert_equals(@sdbm[key], values[i])

      n += 1
    }
    assert_equals(keys.size, n)
    assert_equals(@sdbm, ret)
  end

  def test_keys
    assert_equals([], @sdbm.keys)

    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)

    @sdbm[keys[0]], @sdbm[keys[1]], @sdbm[keys[2]] = values

    assert_equals(keys.sort, @sdbm.keys.sort)
    assert_equals(values.sort, @sdbm.values.sort)
  end

  def test_values
    test_keys
  end

  def test_shift
    assert_nil(@sdbm.shift)
    assert_equals(0, @sdbm.size)

    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)

    @sdbm[keys[0]], @sdbm[keys[1]], @sdbm[keys[2]] = values

    ret_keys = []
    ret_values = []
    while ret = @sdbm.shift
      ret_keys.push ret[0]
      ret_values.push ret[1]

      assert_equals(keys.size - ret_keys.size, @sdbm.size)
    end

    assert_equals(keys.sort, ret_keys.sort)
    assert_equals(values.sort, ret_values.sort)
  end

  def test_delete
    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)
    key = keys[1]

    assert_nil(@sdbm.delete(key))
    assert_equals(0, @sdbm.size)

    @sdbm[keys[0]], @sdbm[keys[1]], @sdbm[keys[2]] = values

    assert_equals('BAR', @sdbm.delete(key))
    assert_nil(@sdbm[key])
    assert_equals(2, @sdbm.size)

    assert_nil(@sdbm.delete(key))
  end
  def test_delete_with_block
    key = 'no called block'
    @sdbm[key] = 'foo'
    assert_equals('foo', @sdbm.delete(key) {|k| k.replace 'called block'})
    assert_equals('no called block', key)
    assert_equals(0, @sdbm.size)

    key = 'no called block'
    assert_equals(:blockval,
		  @sdbm.delete(key) {|k| k.replace 'called block'; :blockval})
    assert_equals('called block', key)
    assert_equals(0, @sdbm.size)
  end

  def test_delete_if
    v = "0"
    100.times {@sdbm[v] = v; v = v.next}

    ret = @sdbm.delete_if {|key, val| key.to_i < 50}
    assert_equals(@sdbm, ret)
    check_size(50, @sdbm)

    ret = @sdbm.delete_if {|key, val| key.to_i >= 50}
    assert_equals(@sdbm, ret)
    check_size(0, @sdbm)

    # break
    v = "0"
    100.times {@sdbm[v] = v; v = v.next}
    check_size(100, @sdbm)
    n = 0;
    @sdbm.delete_if {|key, val|
      break if n > 50
      n+=1
      true
    }
    assert_equals(51, n)
    check_size(49, @sdbm)

    @sdbm.clear

    # raise
    v = "0"
    100.times {@sdbm[v] = v; v = v.next}
    check_size(100, @sdbm)
    n = 0;
    begin
      @sdbm.delete_if {|key, val|
	raise "runtime error" if n > 50
	n+=1
	true
      }
    rescue
    end
    assert_equals(51, n)
    check_size(49, @sdbm)
  end

  def test_reject
    v = "0"
    100.times {@sdbm[v] = v; v = v.next}

    hash = @sdbm.reject {|key, val| key.to_i < 50}
    assert_instance_of(Hash, hash)
    assert_equals(100, @sdbm.size)

    assert_equals(50, hash.size)
    hash.each_pair {|key,val|
      assert_equals(false, key.to_i < 50)
      assert_equals(key, val)
    }

    hash = @sdbm.reject {|key, val| key.to_i < 100}
    assert_instance_of(Hash, hash)
    assert_equals(true, hash.empty?)
  end

  def test_clear
    v = "1"
    100.times {v = v.next; @sdbm[v] = v}

    assert_equals(@sdbm, @sdbm.clear)

    # validate SDBM#size
    i = 0
    @sdbm.each { i += 1 }
    assert_equals(@sdbm.size, i)
    assert_equals(0, i)
  end

  def test_invert
    v = "0"
    100.times {@sdbm[v] = v; v = v.next}

    hash = @sdbm.invert
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

    @sdbm["101"] = "101"
    @sdbm.update hash
    assert_equals(101, @sdbm.size)
    @sdbm.each_pair {|key, val|
      assert_equals(key.to_i, val.to_i)
    }
  end

  def test_replace
    hash = {}
    v = "0"
    100.times {v = v.next; hash[v] = v}

    @sdbm["101"] = "101"
    @sdbm.replace hash
    assert_equals(100, @sdbm.size)
    @sdbm.each_pair {|key, val|
      assert_equals(key.to_i, val.to_i)
    }
  end

  def test_haskey?
    assert_equals('bar', @sdbm['foo']='bar')
    assert_equals(true,  @sdbm.has_key?('foo'))
    assert_equals(false, @sdbm.has_key?('bar'))
  end

  def test_has_value?
    assert_equals('bar', @sdbm['foo']='bar')
    assert_equals(true,  @sdbm.has_value?('bar'))
    assert_equals(false, @sdbm.has_value?('foo'))
  end

  def test_to_a
    v = "0"
    100.times {v = v.next; @sdbm[v] = v}

    ary = @sdbm.to_a
    assert_instance_of(Array, ary)
    assert_equals(100, ary.size)
    ary.each {|key,val|
      assert_equals(key.to_i, val.to_i)
    }
  end

  def test_to_hash
    v = "0"
    100.times {v = v.next; @sdbm[v] = v}

    hash = @sdbm.to_hash
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
    suite.add_test(TestSDBM.suite)
  else
    suite = RUNIT::TestSuite.new
    ARGV.each do |testmethod|
      suite.add_test(TestSDBM.new(testmethod))
    end
  end

  RUNIT::CUI::TestRunner.run(suite)
end
