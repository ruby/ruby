require 'runit/testcase'
require 'runit/cui/testrunner'

if $".grep(/\bgdbm.so\b/).empty?
  begin
    require './gdbm'
  rescue LoadError
    require 'gdbm'
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

class TestGDBM < RUNIT::TestCase
  def setup
    @path = "tmptest_gdbm_"
    assert_instance_of(GDBM, @gdbm = GDBM.new(@path))

    # prepare to make readonly GDBM file
    GDBM.open("tmptest_gdbm_rdonly", 0400) {|gdbm|
      gdbm['foo'] = 'FOO'
    }
    assert_instance_of(GDBM, @gdbm_rdonly = GDBM.new("tmptest_gdbm_rdonly", nil))
  end
  def teardown
    assert_nil(@gdbm.close)
    assert_nil(@gdbm_rdonly.close)
    GC.start
    File.delete *Dir.glob("tmptest_gdbm*").to_a
    p Dir.glob("tmptest_gdbm*") if $DEBUG
  end

  def check_size(expect, gdbm=@gdbm)
    assert_equals(expect, gdbm.size)
    n = 0
    gdbm.each { n+=1 }
    assert_equals(expect, n)
    if expect == 0
      assert_equals(true, gdbm.empty?)
    else
      assert_equals(false, gdbm.empty?)
    end
  end

  def test_version
    STDERR.print GDBM::VERSION
  end

  def test_s_new_has_no_block
    # GDBM.new ignore the block
    foo = true
    assert_instance_of(GDBM, gdbm = GDBM.new("tmptest_gdbm") { foo = false })
    assert_equals(foo, true)
    assert_nil(gdbm.close)
  end
  def test_s_open_create_new
    return if /^CYGWIN_9/ =~ SYSTEM

    save_mask = File.umask(0)
    begin
      assert_instance_of(GDBM, gdbm = GDBM.open("tmptest_gdbm"))
      gdbm.close
      assert_equals(File.stat("tmptest_gdbm").mode & 0777, 0666)
      assert_instance_of(GDBM, gdbm = GDBM.open("tmptest_gdbm2", 0644))
      gdbm.close
      assert_equals(File.stat("tmptest_gdbm2").mode & 0777, 0644)
    ensure
      File.umask save_mask
    end
  end
  def test_s_open_no_create
    # this test is failed on libgdbm 1.8.0
    assert_nil(gdbm = GDBM.open("tmptest_gdbm", nil))
  ensure
    gdbm.close if gdbm
  end
  def test_s_open_3rd_arg
    assert_instance_of(GDBM, gdbm = GDBM.open("tmptest_gdbm", 0644,
					      GDBM::FAST))
    gdbm.close

    # gdbm 1.8.0 specific
    if defined? GDBM::SYNC
      assert_instance_of(GDBM, gdbm = GDBM.open("tmptest_gdbm", 0644,
						GDBM::SYNC))
      gdbm.close
    end
    # gdbm 1.8.0 specific
    if defined? GDBM::NOLOCK
      assert_instance_of(GDBM, gdbm = GDBM.open("tmptest_gdbm", 0644,
						GDBM::NOLOCK))
      gdbm.close
    end
  end
  def test_s_open_with_block
    assert_equals(GDBM.open("tmptest_gdbm") { :foo }, :foo)
  end
  def test_s_open_lock
    fork() {
      assert_instance_of(GDBM, gdbm  = GDBM.open("tmptest_gdbm", 0644))
      sleep 2
    }
    begin
      sleep 1
      assert_exception(Errno::EWOULDBLOCK) {
	begin
	  assert_instance_of(GDBM, gdbm2 = GDBM.open("tmptest_gdbm", 0644))
	rescue Errno::EAGAIN, Errno::EACCES
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
    assert_instance_of(GDBM, gdbm  = GDBM.open("tmptest_gdbm", 0644))
    assert_exception(Errno::EWOULDBLOCK) {
      begin
	GDBM.open("tmptest_gdbm", 0644)
      rescue Errno::EAGAIN
	raise Errno::EWOULDBLOCK
      end
    }
  end
=end

  def test_s_open_nolock
    # gdbm 1.8.0 specific
    if not defined? GDBM::NOLOCK
      return
    end

    fork() {
      assert_instance_of(GDBM, gdbm  = GDBM.open("tmptest_gdbm", 0644,
						GDBM::NOLOCK))
      sleep 2
    }
    sleep 1
    begin
      gdbm2 = nil
      assert_no_exception(Errno::EWOULDBLOCK, Errno::EAGAIN, Errno::EACCES) {
	assert_instance_of(GDBM, gdbm2 = GDBM.open("tmptest_gdbm", 0644))
      }
    ensure
      Process.wait
      gdbm2.close if gdbm2
    end

    p Dir.glob("tmptest_gdbm*") if $DEBUG

    fork() {
      assert_instance_of(GDBM, gdbm  = GDBM.open("tmptest_gdbm", 0644))
      sleep 2
    }
    begin
      sleep 1
      gdbm2 = nil
      assert_no_exception(Errno::EWOULDBLOCK, Errno::EAGAIN, Errno::EACCES) {
	# this test is failed on Cygwin98 (???)
	assert_instance_of(GDBM, gdbm2 = GDBM.open("tmptest_gdbm", 0644,
						   GDBM::NOLOCK))
      }
    ensure
      Process.wait
      gdbm2.close if gdbm2
    end
  end

  def test_s_open_error
    assert_instance_of(GDBM, gdbm = GDBM.open("tmptest_gdbm", 0))
    assert_exception(Errno::EACCES) {
      GDBM.open("tmptest_gdbm", 0)
    }
    gdbm.close
  end

  def test_close
    assert_instance_of(GDBM, gdbm = GDBM.open("tmptest_gdbm"))
    assert_nil(gdbm.close)

    # closed GDBM file
    assert_exception(RuntimeError) { gdbm.close }
  end

  def test_aref
    assert_equals('bar', @gdbm['foo'] = 'bar')
    assert_equals('bar', @gdbm['foo'])

    assert_nil(@gdbm['bar'])
  end

  def test_fetch
    assert_equals('bar', @gdbm['foo']='bar')
    assert_equals('bar', @gdbm.fetch('foo'))

    # key not found
    assert_exception(IndexError) {
      @gdbm.fetch('bar')
    }

    # test for `ifnone' arg
    assert_equals('baz', @gdbm.fetch('bar', 'baz'))

    # test for `ifnone' block
    assert_equals('foobar', @gdbm.fetch('bar') {|key| 'foo' + key })
  end

  def test_aset
    num = 0
    2.times {|i|
      assert_equals('foo', @gdbm['foo'] = 'foo')
      assert_equals('foo', @gdbm['foo'])
      assert_equals('bar', @gdbm['foo'] = 'bar')
      assert_equals('bar', @gdbm['foo'])

      num += 1 if i == 0
      assert_equals(num, @gdbm.size)

      # assign nil
      assert_equals('', @gdbm['bar'] = '')
      assert_equals('', @gdbm['bar'])

      num += 1 if i == 0
      assert_equals(num, @gdbm.size)

      # empty string
      assert_equals('', @gdbm[''] = '')
      assert_equals('', @gdbm[''])

      num += 1 if i == 0
      assert_equals(num, @gdbm.size)

      # Fixnum
      assert_equals('200', @gdbm['100'] = '200')
      assert_equals('200', @gdbm['100'])

      num += 1 if i == 0
      assert_equals(num, @gdbm.size)

      # Big key and value
      assert_equals('y' * 100, @gdbm['x' * 100] = 'y' * 100)
      assert_equals('y' * 100, @gdbm['x' * 100])

      num += 1 if i == 0
      assert_equals(num, @gdbm.size)
    }
  end

  def test_index
    assert_equals('bar', @gdbm['foo'] = 'bar')
    assert_equals('foo', @gdbm.index('bar'))
    assert_nil(@gdbm['bar'])
  end

  def test_indexes
    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)
    @gdbm[keys[0]], @gdbm[keys[1]], @gdbm[keys[2]] = values
    assert_equals(values.reverse, @gdbm.indexes(*keys.reverse))
  end

  def test_values_at
    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)
    @gdbm[keys[0]], @gdbm[keys[1]], @gdbm[keys[2]] = values
    assert_equals(values.reverse, @gdbm.values_at(*keys.reverse))
  end

  def test_select_with_block
    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)
    @gdbm[keys[0]], @gdbm[keys[1]], @gdbm[keys[2]] = values
    ret = @gdbm.select {|k,v|
      assert_equals(k.upcase, v)
      k != "bar"
    }
    assert_equals([['baz', 'BAZ'], ['foo', 'FOO']],
		  ret.sort)
  end

  def test_length
    num = 10
    assert_equals(0, @gdbm.size)
    num.times {|i|
      i = i.to_s
      @gdbm[i] = i
    }
    assert_equals(num, @gdbm.size)

    @gdbm.shift

    assert_equals(num - 1, @gdbm.size)
  end

  def test_empty?
    assert_equals(true, @gdbm.empty?)
    @gdbm['foo'] = 'FOO'
    assert_equals(false, @gdbm.empty?)
  end

  def test_each_pair
    n = 0
    @gdbm.each_pair { n += 1 }
    assert_equals(0, n)

    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)

    @gdbm[keys[0]], @gdbm[keys[1]], @gdbm[keys[2]] = values

    n = 0
    ret = @gdbm.each_pair {|key, val|
      assert_not_nil(i = keys.index(key))
      assert_equals(val, values[i])

      n += 1
    }
    assert_equals(keys.size, n)
    assert_equals(@gdbm, ret)
  end

  def test_each_value
    n = 0
    @gdbm.each_value { n += 1 }
    assert_equals(0, n)

    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)

    @gdbm[keys[0]], @gdbm[keys[1]], @gdbm[keys[2]] = values

    n = 0
    ret = @gdbm.each_value {|val|
      assert_not_nil(key = @gdbm.index(val))
      assert_not_nil(i = keys.index(key))
      assert_equals(val, values[i])

      n += 1
    }
    assert_equals(keys.size, n)
    assert_equals(@gdbm, ret)
  end

  def test_each_key
    n = 0
    @gdbm.each_key { n += 1 }
    assert_equals(0, n)

    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)

    @gdbm[keys[0]], @gdbm[keys[1]], @gdbm[keys[2]] = values

    n = 0
    ret = @gdbm.each_key {|key|
      assert_not_nil(i = keys.index(key))
      assert_equals(@gdbm[key], values[i])

      n += 1
    }
    assert_equals(keys.size, n)
    assert_equals(@gdbm, ret)
  end

  def test_keys
    assert_equals([], @gdbm.keys)

    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)

    @gdbm[keys[0]], @gdbm[keys[1]], @gdbm[keys[2]] = values

    assert_equals(keys.sort, @gdbm.keys.sort)
    assert_equals(values.sort, @gdbm.values.sort)
  end

  def test_values
    test_keys
  end

  def test_shift
    assert_nil(@gdbm.shift)
    assert_equals(0, @gdbm.size)

    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)

    @gdbm[keys[0]], @gdbm[keys[1]], @gdbm[keys[2]] = values

    ret_keys = []
    ret_values = []
    while ret = @gdbm.shift
      ret_keys.push ret[0]
      ret_values.push ret[1]

      assert_equals(keys.size - ret_keys.size, @gdbm.size)
    end

    assert_equals(keys.sort, ret_keys.sort)
    assert_equals(values.sort, ret_values.sort)
  end

  def test_delete
    keys = %w(foo bar baz)
    values = %w(FOO BAR BAZ)
    key = keys[1]

    assert_nil(@gdbm.delete(key))
    assert_equals(0, @gdbm.size)

    @gdbm[keys[0]], @gdbm[keys[1]], @gdbm[keys[2]] = values

    assert_equals('BAR', @gdbm.delete(key))
    assert_nil(@gdbm[key])
    assert_equals(2, @gdbm.size)

    assert_nil(@gdbm.delete(key))

    if /^CYGWIN_9/ !~ SYSTEM
      assert_exception(GDBMError) {
	@gdbm_rdonly.delete("foo")
      }

      assert_nil(@gdbm_rdonly.delete("bar"))
    end
  end
  def test_delete_with_block
    key = 'no called block'
    @gdbm[key] = 'foo'
    assert_equals('foo', @gdbm.delete(key) {|k| k.replace 'called block'})
    assert_equals('no called block', key)
    assert_equals(0, @gdbm.size)

    key = 'no called block'
    assert_equals(:blockval,
		  @gdbm.delete(key) {|k| k.replace 'called block'; :blockval})
    assert_equals('called block', key)
    assert_equals(0, @gdbm.size)
  end

  def test_delete_if
    v = "0"
    100.times {@gdbm[v] = v; v = v.next}

    ret = @gdbm.delete_if {|key, val| key.to_i < 50}
    assert_equals(@gdbm, ret)
    check_size(50, @gdbm)

    ret = @gdbm.delete_if {|key, val| key.to_i >= 50}
    assert_equals(@gdbm, ret)
    check_size(0, @gdbm)

    # break
    v = "0"
    100.times {@gdbm[v] = v; v = v.next}
    check_size(100, @gdbm)
    n = 0;
    @gdbm.delete_if {|key, val|
      break if n > 50
      n+=1
      true
    }
    assert_equals(51, n)
    check_size(49, @gdbm)

    @gdbm.clear

    # raise
    v = "0"
    100.times {@gdbm[v] = v; v = v.next}
    check_size(100, @gdbm)
    n = 0;
    begin
      @gdbm.delete_if {|key, val|
	raise "runtime error" if n > 50
	n+=1
	true
      }
    rescue
    end
    assert_equals(51, n)
    check_size(49, @gdbm)
  end

  def test_reject
    v = "0"
    100.times {@gdbm[v] = v; v = v.next}

    hash = @gdbm.reject {|key, val| key.to_i < 50}
    assert_instance_of(Hash, hash)
    assert_equals(100, @gdbm.size)

    assert_equals(50, hash.size)
    hash.each_pair {|key,val|
      assert_equals(false, key.to_i < 50)
      assert_equals(key, val)
    }

    hash = @gdbm.reject {|key, val| key.to_i < 100}
    assert_instance_of(Hash, hash)
    assert_equals(true, hash.empty?)
  end

  def test_clear
    v = "1"
    100.times {v = v.next; @gdbm[v] = v}

    assert_equals(@gdbm, @gdbm.clear)

    # validate GDBM#size
    i = 0
    @gdbm.each { i += 1 }
    assert_equals(@gdbm.size, i)
    assert_equals(0, i)
  end

  def test_invert
    v = "0"
    100.times {@gdbm[v] = v; v = v.next}

    hash = @gdbm.invert
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

    @gdbm["101"] = "101"
    @gdbm.update hash
    assert_equals(101, @gdbm.size)
    @gdbm.each_pair {|key, val|
      assert_equals(key.to_i, val.to_i)
    }
  end

  def test_replace
    hash = {}
    v = "0"
    100.times {v = v.next; hash[v] = v}

    @gdbm["101"] = "101"
    @gdbm.replace hash
    assert_equals(100, @gdbm.size)
    @gdbm.each_pair {|key, val|
      assert_equals(key.to_i, val.to_i)
    }
  end

  def test_reorganize
    size1 = File.size(@path)
    i = "1"
    1000.times {i = i.next; @gdbm[i] = i}
    @gdbm.clear
    @gdbm.sync

    size2 = File.size(@path)
    @gdbm.reorganize
    size3 = File.size(@path)

    # p [size1, size2, size3]
    assert_equals(true, size1 < size2)
    # this test is failed on Cygwin98. `GDBM version 1.8.0, as of May 19, 1999'
    assert_equals(true, size3 < size2)
    assert_equals(size1, size3)
  end

  def test_sync
    assert_instance_of(GDBM, gdbm = GDBM.open('tmptest_gdbm', 0666, GDBM::FAST))
    assert_equals(gdbm.sync, gdbm)
    gdbm.close
    assert_instance_of(GDBM, gdbm = GDBM.open('tmptest_gdbm', 0666))
    assert_equals(gdbm.sync, gdbm)
    gdbm.close
  end

  def test_cachesize=
      assert_equals(@gdbm.cachesize = 1024, 1024)
  end

  def test_fastmode=
      assert_equals(@gdbm.fastmode = true, true)
  end

  def test_syncmode=
      assert_equals(@gdbm.syncmode = true, true)
  end

  def test_haskey?
    assert_equals('bar', @gdbm['foo']='bar')
    assert_equals(true,  @gdbm.has_key?('foo'))
    assert_equals(false, @gdbm.has_key?('bar'))
  end

  def test_has_value?
    assert_equals('bar', @gdbm['foo']='bar')
    assert_equals(true,  @gdbm.has_value?('bar'))
    assert_equals(false, @gdbm.has_value?('foo'))
  end

  def test_to_a
    v = "0"
    100.times {v = v.next; @gdbm[v] = v}

    ary = @gdbm.to_a
    assert_instance_of(Array, ary)
    assert_equals(100, ary.size)
    ary.each {|key,val|
      assert_equals(key.to_i, val.to_i)
    }
  end

  def test_to_hash
    v = "0"
    100.times {v = v.next; @gdbm[v] = v}

    hash = @gdbm.to_hash
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
    suite.add_test(TestGDBM.suite)
  else
    suite = RUNIT::TestSuite.new
    ARGV.each do |testmethod|
      suite.add_test(TestGDBM.new(testmethod))
    end
  end

  RUNIT::CUI::TestRunner.run(suite)
end
