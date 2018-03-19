# -*- coding: us-ascii -*-
# frozen_string_literal: false
require 'test/unit'
EnvUtil.suppress_warning {require 'continuation'}

class TestHash < Test::Unit::TestCase

  def test_hash
    x = @cls[1=>2, 2=>4, 3=>6]
    y = @cls[1=>2, 2=>4, 3=>6] # y = {1, 2, 2, 4, 3, 6} # 1.9 doesn't support

    assert_equal(2, x[1])

    assert(begin
         for k,v in y
           raise if k*2 != v
         end
         true
       rescue
         false
       end)

    assert_equal(3, x.length)
    assert_send([x, :has_key?, 1])
    assert_send([x, :has_value?, 4])
    assert_equal([4,6], x.values_at(2,3))
    assert_equal({1=>2, 2=>4, 3=>6}, x)

    z = y.keys.join(":")
    assert_equal("1:2:3", z)

    z = y.values.join(":")
    assert_equal("2:4:6", z)
    assert_equal(x, y)

    y.shift
    assert_equal(2, y.length)

    z = [1,2]
    y[z] = 256
    assert_equal(256, y[z])

    x = Hash.new(0)
    x[1] = 1
    assert_equal(1, x[1])
    assert_equal(0, x[2])

    x = Hash.new([])
    assert_equal([], x[22])
    assert_same(x[22], x[22])

    x = Hash.new{[]}
    assert_equal([], x[22])
    assert_not_same(x[22], x[22])

    x = Hash.new{|h,kk| z = kk; h[kk] = kk*2}
    z = 0
    assert_equal(44, x[22])
    assert_equal(22, z)
    z = 0
    assert_equal(44, x[22])
    assert_equal(0, z)
    x.default = 5
    assert_equal(5, x[23])

    x = Hash.new
    def x.default(k)
      $z = k
      self[k] = k*2
    end
    $z = 0
    assert_equal(44, x[22])
    assert_equal(22, $z)
    $z = 0
    assert_equal(44, x[22])
    assert_equal(0, $z)
  end

  # From rubicon

  def setup
    @cls ||= Hash
    @h = @cls[
      1 => 'one', 2 => 'two', 3 => 'three',
      self => 'self', true => 'true', nil => 'nil',
      'nil' => nil
    ]
    @verbose = $VERBOSE
    $VERBOSE = nil
  end

  def teardown
    $VERBOSE = @verbose
  end

  def test_bad_initialize_copy
    h = Class.new(Hash) {
      def initialize_copy(h)
        super(Object.new)
      end
    }.new
    assert_raise(TypeError) { h.dup }
  end

  def test_clear_initialize_copy
    h = @cls[1=>2]
    h.instance_eval {initialize_copy({})}
    assert_empty(h)
  end

  def test_self_initialize_copy
    h = @cls[1=>2]
    h.instance_eval {initialize_copy(h)}
    assert_equal(2, h[1])
  end

  def test_dup_will_rehash
    set1 = @cls[]
    set2 = @cls[set1 => true]

    set1[set1] = true

    assert_equal set2, set2.dup
  end

  def test_s_AREF
    h = @cls["a" => 100, "b" => 200]
    assert_equal(100, h['a'])
    assert_equal(200, h['b'])
    assert_nil(h['c'])

    h = @cls.[]("a" => 100, "b" => 200)
    assert_equal(100, h['a'])
    assert_equal(200, h['b'])
    assert_nil(h['c'])
  end

  def test_s_new
    h = @cls.new
    assert_instance_of(@cls, h)
    assert_nil(h.default)
    assert_nil(h['spurious'])

    h = @cls.new('default')
    assert_instance_of(@cls, h)
    assert_equal('default', h.default)
    assert_equal('default', h['spurious'])

  end

  def test_try_convert
    assert_equal({1=>2}, Hash.try_convert({1=>2}))
    assert_equal(nil, Hash.try_convert("1=>2"))
    o = Object.new
    def o.to_hash; {3=>4} end
    assert_equal({3=>4}, Hash.try_convert(o))
  end

  def test_AREF # '[]'
    t = Time.now
    h = @cls[
      1 => 'one', 2 => 'two', 3 => 'three',
      self => 'self', t => 'time', nil => 'nil',
      'nil' => nil
    ]

    assert_equal('one',   h[1])
    assert_equal('two',   h[2])
    assert_equal('three', h[3])
    assert_equal('self',  h[self])
    assert_equal('time',  h[t])
    assert_equal('nil',   h[nil])
    assert_equal(nil,     h['nil'])
    assert_equal(nil,     h['koala'])

    h1 = h.dup
    h1.default = :default

    assert_equal('one',    h1[1])
    assert_equal('two',    h1[2])
    assert_equal('three',  h1[3])
    assert_equal('self',   h1[self])
    assert_equal('time',   h1[t])
    assert_equal('nil',    h1[nil])
    assert_equal(nil,      h1['nil'])
    assert_equal(:default, h1['koala'])


  end

  def test_ASET # '[]='
    t = Time.now
    h = @cls.new
    h[1]     = 'one'
    h[2]     = 'two'
    h[3]     = 'three'
    h[self]  = 'self'
    h[t]     = 'time'
    h[nil]   = 'nil'
    h['nil'] = nil
    assert_equal('one',   h[1])
    assert_equal('two',   h[2])
    assert_equal('three', h[3])
    assert_equal('self',  h[self])
    assert_equal('time',  h[t])
    assert_equal('nil',   h[nil])
    assert_equal(nil,     h['nil'])
    assert_equal(nil,     h['koala'])

    h[1] = 1
    h[nil] = 99
    h['nil'] = nil
    z = [1,2]
    h[z] = 256
    assert_equal(1,       h[1])
    assert_equal('two',   h[2])
    assert_equal('three', h[3])
    assert_equal('self',  h[self])
    assert_equal('time',  h[t])
    assert_equal(99,      h[nil])
    assert_equal(nil,     h['nil'])
    assert_equal(nil,     h['koala'])
    assert_equal(256,     h[z])
  end

  def test_AREF_fstring_key
    h = {"abc" => 1}
    before = GC.stat(:total_allocated_objects)
    5.times{ h["abc"] }
    assert_equal before, GC.stat(:total_allocated_objects)
  end

  def test_ASET_fstring_key
    a, b = {}, {}
    assert_equal 1, a["abc"] = 1
    assert_equal 1, b["abc"] = 1
    assert_same a.keys[0], b.keys[0]
  end

  def test_hash_aset_fstring_identity
    h = {}.compare_by_identity
    h['abc'] = 1
    h['abc'] = 2
    assert_equal 2, h.size, '[ruby-core:78783] [Bug #12855]'
  end

  def test_hash_aref_fstring_identity
    h = {}.compare_by_identity
    h['abc'] = 1
    assert_nil h['abc'], '[ruby-core:78783] [Bug #12855]'
  end

  def test_NEWHASH_fstring_key
    a = {"ABC" => :t}
    b = {"ABC" => :t}
    assert_same a.keys[0], b.keys[0]
    assert_same "ABC".freeze, a.keys[0]
  end

  def test_EQUAL # '=='
    h1 = @cls[ "a" => 1, "c" => 2 ]
    h2 = @cls[ "a" => 1, "c" => 2, 7 => 35 ]
    h3 = @cls[ "a" => 1, "c" => 2, 7 => 35 ]
    h4 = @cls[ ]
    assert_equal(h1, h1)
    assert_equal(h2, h2)
    assert_equal(h3, h3)
    assert_equal(h4, h4)
    assert_not_equal(h1, h2)
    assert_equal(h2, h3)
    assert_not_equal(h3, h4)
  end

  def test_clear
    assert_operator(@h.size, :>, 0)
    @h.clear
    assert_equal(0, @h.size)
    assert_nil(@h[1])
  end

  def test_clone
    for taint in [ false, true ]
      for frozen in [ false, true ]
        a = @h.clone
        a.taint  if taint
        a.freeze if frozen
        b = a.clone

        assert_equal(a, b)
        assert_not_same(a, b)
        assert_equal(a.frozen?, b.frozen?)
        assert_equal(a.tainted?, b.tainted?)
      end
    end
  end

  def test_default
    assert_nil(@h.default)
    h = @cls.new(:xyzzy)
    assert_equal(:xyzzy, h.default)
  end

  def test_default=
    assert_nil(@h.default)
    @h.default = :xyzzy
    assert_equal(:xyzzy, @h.default)
  end

  def test_delete
    h1 = @cls[ 1 => 'one', 2 => 'two', true => 'true' ]
    h2 = @cls[ 1 => 'one', 2 => 'two' ]
    h3 = @cls[ 2 => 'two' ]

    assert_equal('true', h1.delete(true))
    assert_equal(h2, h1)

    assert_equal('one', h1.delete(1))
    assert_equal(h3, h1)

    assert_equal('two', h1.delete(2))
    assert_equal(@cls[], h1)

    assert_nil(h1.delete(99))
    assert_equal(@cls[], h1)

    assert_equal('default 99', h1.delete(99) {|i| "default #{i}" })
  end

  def test_delete_if
    base = @cls[ 1 => 'one', 2 => false, true => 'true', 'cat' => 99 ]
    h1   = @cls[ 1 => 'one', 2 => false, true => 'true' ]
    h2   = @cls[ 2 => false, 'cat' => 99 ]
    h3   = @cls[ 2 => false ]

    h = base.dup
    assert_equal(h, h.delete_if { false })
    assert_equal(@cls[], h.delete_if { true })

    h = base.dup
    assert_equal(h1, h.delete_if {|k,v| k.instance_of?(String) })
    assert_equal(h1, h)

    h = base.dup
    assert_equal(h2, h.delete_if {|k,v| v.instance_of?(String) })
    assert_equal(h2, h)

    h = base.dup
    assert_equal(h3, h.delete_if {|k,v| v })
    assert_equal(h3, h)

    h = base.dup
    n = 0
    h.delete_if {|*a|
      n += 1
      assert_equal(2, a.size)
      assert_equal(base[a[0]], a[1])
      h.shift
      true
    }
    assert_equal(base.size, n)
  end

  def test_keep_if
    h = @cls[1=>2,3=>4,5=>6]
    assert_equal({3=>4,5=>6}, h.keep_if {|k, v| k + v >= 7 })
    h = @cls[1=>2,3=>4,5=>6]
    assert_equal({1=>2,3=>4,5=>6}, h.keep_if{true})
  end

  def test_compact
    h = @cls[a: 1, b: nil, c: false, d: true, e: nil]
    assert_equal({a: 1, c: false, d: true}, h.compact)
    assert_equal({a: 1, b: nil, c: false, d: true, e: nil}, h)
    assert_same(h, h.compact!)
    assert_equal({a: 1, c: false, d: true}, h)
    assert_nil(h.compact!)
  end

  def test_dup
    for taint in [ false, true ]
      for frozen in [ false, true ]
        a = @h.dup
        a.taint  if taint
        a.freeze if frozen
        b = a.dup

        assert_equal(a, b)
        assert_not_same(a, b)
        assert_equal(false, b.frozen?)
        assert_equal(a.tainted?, b.tainted?)
      end
    end
  end

  def test_dup_equality
    h = @cls['k' => 'v']
    assert_equal(h, h.dup)
    h1 = @cls[h => 1]
    assert_equal(h1, h1.dup)
    h[1] = 2
    assert_equal(h1, h1.dup)
  end

  def test_each
    count = 0
    @cls[].each { |k, v| count + 1 }
    assert_equal(0, count)

    h = @h
    h.each do |k, v|
      assert_equal(v, h.delete(k))
    end
    assert_equal(@cls[], h)

    h = @cls[]
    h[1] = 1
    h[2] = 2
    assert_equal([[1,1],[2,2]], h.each.to_a)
  end

  def test_each_key
    count = 0
    @cls[].each_key { |k| count + 1 }
    assert_equal(0, count)

    h = @h
    h.each_key do |k|
      h.delete(k)
    end
    assert_equal(@cls[], h)
  end

  def test_each_pair
    count = 0
    @cls[].each_pair { |k, v| count + 1 }
    assert_equal(0, count)

    h = @h
    h.each_pair do |k, v|
      assert_equal(v, h.delete(k))
    end
    assert_equal(@cls[], h)
  end

  def test_each_value
    res = []
    @cls[].each_value { |v| res << v }
    assert_equal(0, [].length)

    @h.each_value { |v| res << v }
    assert_equal(0, [].length)

    expected = []
    @h.each { |k, v| expected << v }

    assert_equal([], expected - res)
    assert_equal([], res - expected)
  end

  def test_empty?
    assert_empty(@cls[])
    assert_not_empty(@h)
  end

  def test_fetch
    assert_equal('gumbygumby', @h.fetch('gumby') {|k| k * 2 })
    assert_equal('pokey', @h.fetch('gumby', 'pokey'))

    assert_equal('one', @h.fetch(1))
    assert_equal(nil, @h.fetch('nil'))
    assert_equal('nil', @h.fetch(nil))
  end

  def test_fetch_error
    assert_raise(KeyError) { @cls[].fetch(1) }
    assert_raise(KeyError) { @h.fetch('gumby') }
    e = assert_raise(KeyError) { @h.fetch('gumby'*20) }
    assert_match(/key not found: "gumbygumby/, e.message)
    assert_match(/\.\.\.\z/, e.message)
  end

  def test_key2?
    assert_not_send([@cls[], :key?, 1])
    assert_not_send([@cls[], :key?, nil])
    assert_send([@h, :key?, nil])
    assert_send([@h, :key?, 1])
    assert_not_send([@h, :key?, 'gumby'])
  end

  def test_value?
    assert_not_send([@cls[], :value?, 1])
    assert_not_send([@cls[], :value?, nil])
    assert_send([@h, :value?, 'one'])
    assert_send([@h, :value?, nil])
    assert_not_send([@h, :value?, 'gumby'])
  end

  def test_include?
    assert_not_send([@cls[], :include?, 1])
    assert_not_send([@cls[], :include?, nil])
    assert_send([@h, :include?, nil])
    assert_send([@h, :include?, 1])
    assert_not_send([@h, :include?, 'gumby'])
  end

  def test_key
    assert_equal(1,     @h.key('one'))
    assert_equal(nil,   @h.key('nil'))
    assert_equal('nil', @h.key(nil))

    assert_equal(nil,   @h.key('gumby'))
    assert_equal(nil,   @cls[].key('gumby'))
  end

  def test_values_at
    res = @h.values_at('dog', 'cat', 'horse')
    assert_equal(3, res.length)
    assert_equal([nil, nil, nil], res)

    res = @h.values_at
    assert_equal(0, res.length)

    res = @h.values_at(3, 2, 1, nil)
    assert_equal 4, res.length
    assert_equal %w( three two one nil ), res

    res = @h.values_at(3, 99, 1, nil)
    assert_equal 4, res.length
    assert_equal ['three', nil, 'one', 'nil'], res
  end

  def test_fetch_values
    res = @h.fetch_values
    assert_equal(0, res.length)

    res = @h.fetch_values(3, 2, 1, nil)
    assert_equal(4, res.length)
    assert_equal %w( three two one nil ), res

    assert_raise KeyError do
      @h.fetch_values(3, 'invalid')
    end

    res = @h.fetch_values(3, 'invalid') { |k| k.upcase }
    assert_equal %w( three INVALID ), res
  end

  def test_invert
    h = @h.invert
    assert_equal(1, h['one'])
    assert_equal(true, h['true'])
    assert_equal(nil,  h['nil'])

    h.each do |k, v|
      assert_send([@h, :key?, v])    # not true in general, but works here
    end

    h = @cls[ 'a' => 1, 'b' => 2, 'c' => 1].invert
    assert_equal(2, h.length)
    assert_include(%w[a c], h[1])
    assert_equal('b', h[2])
  end

  def test_key?
    assert_not_send([@cls[], :key?, 1])
    assert_not_send([@cls[], :key?, nil])
    assert_send([@h, :key?, nil])
    assert_send([@h, :key?, 1])
    assert_not_send([@h, :key?, 'gumby'])
  end

  def test_keys
    assert_equal([], @cls[].keys)

    keys = @h.keys
    expected = []
    @h.each { |k, v| expected << k }
    assert_equal([], keys - expected)
    assert_equal([], expected - keys)
  end

  def test_length
    assert_equal(0, @cls[].length)
    assert_equal(7, @h.length)
  end

  def test_member?
    assert_not_send([@cls[], :member?, 1])
    assert_not_send([@cls[], :member?, nil])
    assert_send([@h, :member?, nil])
    assert_send([@h, :member?, 1])
    assert_not_send([@h, :member?, 'gumby'])
  end

  def test_rehash
    a = [ "a", "b" ]
    c = [ "c", "d" ]
    h = @cls[ a => 100, c => 300 ]
    assert_equal(100, h[a])
    a[0] = "z"
    assert_nil(h[a])
    h.rehash
    assert_equal(100, h[a])
  end

  def test_reject
    assert_equal({3=>4,5=>6}, @cls[1=>2,3=>4,5=>6].reject {|k, v| k + v < 7 })

    base = @cls[ 1 => 'one', 2 => false, true => 'true', 'cat' => 99 ]
    h1   = @cls[ 1 => 'one', 2 => false, true => 'true' ]
    h2   = @cls[ 2 => false, 'cat' => 99 ]
    h3   = @cls[ 2 => false ]

    h = base.dup
    assert_equal(h, h.reject { false })
    assert_equal(@cls[], h.reject { true })

    h = base.dup
    assert_equal(h1, h.reject {|k,v| k.instance_of?(String) })

    assert_equal(h2, h.reject {|k,v| v.instance_of?(String) })

    assert_equal(h3, h.reject {|k,v| v })
    assert_equal(base, h)

    h.instance_variable_set(:@foo, :foo)
    h.default = 42
    h.taint
    h = EnvUtil.suppress_warning {h.reject {false}}
    assert_instance_of(Hash, h)
    assert_not_predicate(h, :tainted?)
    assert_nil(h.default)
    assert_not_send([h, :instance_variable_defined?, :@foo])
  end

  def test_reject!
    base = @cls[ 1 => 'one', 2 => false, true => 'true', 'cat' => 99 ]
    h1   = @cls[ 1 => 'one', 2 => false, true => 'true' ]
    h2   = @cls[ 2 => false, 'cat' => 99 ]
    h3   = @cls[ 2 => false ]

    h = base.dup
    assert_equal(nil, h.reject! { false })
    assert_equal(@cls[],  h.reject! { true })

    h = base.dup
    assert_equal(h1, h.reject! {|k,v| k.instance_of?(String) })
    assert_equal(h1, h)

    h = base.dup
    assert_equal(h2, h.reject! {|k,v| v.instance_of?(String) })
    assert_equal(h2, h)

    h = base.dup
    assert_equal(h3, h.reject! {|k,v| v })
    assert_equal(h3, h)
  end

  def test_replace
    h = @cls[ 1 => 2, 3 => 4 ]
    h1 = h.replace(@cls[ 9 => 8, 7 => 6 ])
    assert_equal(h, h1)
    assert_equal(8, h[9])
    assert_equal(6, h[7])
    assert_nil(h[1])
    assert_nil(h[2])
  end

  def test_replace_bug9230
    h = @cls[]
    h.replace(@cls[])
    assert_empty h

    h = @cls[]
    h.replace(@cls[].compare_by_identity)
    assert_predicate(h, :compare_by_identity?)
  end

  def test_shift
    h = @h.dup

    @h.length.times {
      k, v = h.shift
      assert_send([@h, :key?, k])
      assert_equal(@h[k], v)
    }

    assert_equal(0, h.length)
  end

  def test_size
    assert_equal(0, @cls[].length)
    assert_equal(7, @h.length)
  end

  def test_sort
    h = @cls[].sort
    assert_equal([], h)

    h = @cls[ 1 => 1, 2 => 1 ].sort
    assert_equal([[1,1], [2,1]], h)

    h = @cls[ 'cat' => 'feline', 'ass' => 'asinine', 'bee' => 'beeline' ]
    h1 = h.sort
    assert_equal([ %w(ass asinine), %w(bee beeline), %w(cat feline)], h1)
  end

  def test_store
    t = Time.now
    h = @cls.new
    h.store(1, 'one')
    h.store(2, 'two')
    h.store(3, 'three')
    h.store(self, 'self')
    h.store(t,  'time')
    h.store(nil, 'nil')
    h.store('nil', nil)
    assert_equal('one',   h[1])
    assert_equal('two',   h[2])
    assert_equal('three', h[3])
    assert_equal('self',  h[self])
    assert_equal('time',  h[t])
    assert_equal('nil',   h[nil])
    assert_equal(nil,     h['nil'])
    assert_equal(nil,     h['koala'])

    h.store(1, 1)
    h.store(nil,  99)
    h.store('nil', nil)
    assert_equal(1,       h[1])
    assert_equal('two',   h[2])
    assert_equal('three', h[3])
    assert_equal('self',  h[self])
    assert_equal('time',  h[t])
    assert_equal(99,      h[nil])
    assert_equal(nil,     h['nil'])
    assert_equal(nil,     h['koala'])
  end

  def test_to_a
    assert_equal([], @cls[].to_a)
    assert_equal([[1,2]], @cls[ 1=>2 ].to_a)
    a = @cls[ 1=>2, 3=>4, 5=>6 ].to_a
    assert_equal([1,2], a.delete([1,2]))
    assert_equal([3,4], a.delete([3,4]))
    assert_equal([5,6], a.delete([5,6]))
    assert_equal(0, a.length)

    h = @cls[ 1=>2, 3=>4, 5=>6 ]
    h.taint
    a = h.to_a
    assert_equal(true, a.tainted?)
  end

  def test_to_hash
    h = @h.to_hash
    assert_equal(@h, h)
    assert_instance_of(@cls, h)
  end

  def test_to_h
    h = @h.to_h
    assert_equal(@h, h)
    assert_instance_of(Hash, h)
  end

  def test_to_h_instance_variable
    @h.instance_variable_set(:@x, 42)
    h = @h.to_h
    if @cls == Hash
      assert_equal(42, h.instance_variable_get(:@x))
    else
      assert_not_send([h, :instance_variable_defined?, :@x])
    end
  end

  def test_to_h_default_value
    @h.default = :foo
    h = @h.to_h
    assert_equal(:foo, h.default)
  end

  def test_to_h_default_proc
    @h.default_proc = ->(_,k) {"nope#{k}"}
    h = @h.to_h
    assert_equal("nope42", h[42])
  end

  def test_nil_to_h
    h = nil.to_h
    assert_equal({}, h)
    assert_nil(h.default)
    assert_nil(h.default_proc)
  end

  def test_to_s
    h = @cls[ 1 => 2, "cat" => "dog", 1.5 => :fred ]
    assert_equal(h.inspect, h.to_s)
    $, = ":"
    assert_equal(h.inspect, h.to_s)
    h = @cls[]
    assert_equal(h.inspect, h.to_s)
  ensure
    $, = nil
  end

  def test_update
    h1 = @cls[ 1 => 2, 2 => 3, 3 => 4 ]
    h2 = @cls[ 2 => 'two', 4 => 'four' ]

    ha = @cls[ 1 => 2, 2 => 'two', 3 => 4, 4 => 'four' ]
    hb = @cls[ 1 => 2, 2 => 3, 3 => 4, 4 => 'four' ]

    assert_equal(ha, h1.update(h2))
    assert_equal(ha, h1)

    h1 = @cls[ 1 => 2, 2 => 3, 3 => 4 ]
    h2 = @cls[ 2 => 'two', 4 => 'four' ]

    assert_equal(hb, h2.update(h1))
    assert_equal(hb, h2)
  end

  def test_value2?
    assert_not_send([@cls[], :value?, 1])
    assert_not_send([@cls[], :value?, nil])
    assert_send([@h, :value?, nil])
    assert_send([@h, :value?, 'one'])
    assert_not_send([@h, :value?, 'gumby'])
  end

  def test_values
    assert_equal([], @cls[].values)

    vals = @h.values
    expected = []
    @h.each { |k, v| expected << v }
    assert_equal([], vals - expected)
    assert_equal([], expected - vals)
  end

  def test_initialize_wrong_arguments
    assert_raise(ArgumentError) do
      Hash.new(0) { }
    end
  end

  def test_create
    assert_equal({1=>2, 3=>4}, @cls[[[1,2],[3,4]]])
    assert_raise(ArgumentError) { Hash[0, 1, 2] }
    assert_warning(/wrong element type Integer at 1 /) {@cls[[[1, 2], 3]]}
    bug5406 = '[ruby-core:39945]'
    assert_raise(ArgumentError, bug5406) { @cls[[[1, 2], [3, 4, 5]]] }
    assert_equal({1=>2, 3=>4}, @cls[1,2,3,4])
    o = Object.new
    def o.to_hash() {1=>2} end
    assert_equal({1=>2}, @cls[o], "[ruby-dev:34555]")
  end

  def test_rehash2
    h = @cls[1 => 2, 3 => 4]
    assert_equal(h.dup, h.rehash)
    assert_raise(RuntimeError) { h.each { h.rehash } }
    assert_equal({}, @cls[].rehash)
  end

  def test_fetch2
    assert_equal(:bar, @h.fetch(0, :foo) { :bar })
  end

  def test_default_proc
    h = @cls.new {|hh, k| hh + k + "baz" }
    assert_equal("foobarbaz", h.default_proc.call("foo", "bar"))
    assert_nil(h.default_proc = nil)
    assert_nil(h.default_proc)
    h.default_proc = ->(_,_){ true }
    assert_equal(true, h[:nope])
    h = @cls[]
    assert_nil(h.default_proc)
  end

  def test_shift2
    h = @cls.new {|hh, k| :foo }
    h[1] = 2
    assert_equal([1, 2], h.shift)
    assert_equal(:foo, h.shift)
    assert_equal(:foo, h.shift)

    h = @cls.new(:foo)
    h[1] = 2
    assert_equal([1, 2], h.shift)
    assert_equal(:foo, h.shift)
    assert_equal(:foo, h.shift)

    h =@cls[1=>2]
    h.each { assert_equal([1, 2], h.shift) }
  end

  def test_shift_none
    h = @cls.new {|hh, k| "foo"}
    def h.default(k = nil)
      super.upcase
    end
    assert_equal("FOO", h.shift)
  end

  def test_reject_bang2
    assert_equal({1=>2}, @cls[1=>2,3=>4].reject! {|k, v| k + v == 7 })
    assert_nil(@cls[1=>2,3=>4].reject! {|k, v| k == 5 })
    assert_nil(@cls[].reject! { })
  end

  def test_select
    assert_equal({3=>4,5=>6}, @cls[1=>2,3=>4,5=>6].select {|k, v| k + v >= 7 })

    base = @cls[ 1 => 'one', '2' => false, true => 'true', 'cat' => 99 ]
    h1   = @cls[ '2' => false, 'cat' => 99 ]
    h2   = @cls[ 1 => 'one', true => 'true' ]
    h3   = @cls[ 1 => 'one', true => 'true', 'cat' => 99 ]

    h = base.dup
    assert_equal(h, h.select { true })
    assert_equal(@cls[], h.select { false })

    h = base.dup
    assert_equal(h1, h.select {|k,v| k.instance_of?(String) })

    assert_equal(h2, h.select {|k,v| v.instance_of?(String) })

    assert_equal(h3, h.select {|k,v| v })
    assert_equal(base, h)

    h.instance_variable_set(:@foo, :foo)
    h.default = 42
    h.taint
    h = h.select {true}
    assert_instance_of(Hash, h)
    assert_not_predicate(h, :tainted?)
    assert_nil(h.default)
    assert_not_send([h, :instance_variable_defined?, :@foo])
  end

  def test_select!
    h = @cls[1=>2,3=>4,5=>6]
    assert_equal(h, h.select! {|k, v| k + v >= 7 })
    assert_equal({3=>4,5=>6}, h)
    h = @cls[1=>2,3=>4,5=>6]
    assert_equal(nil, h.select!{true})
  end

  def test_clear2
    assert_equal({}, @cls[1=>2,3=>4,5=>6].clear)
    h = @cls[1=>2,3=>4,5=>6]
    h.each { h.clear }
    assert_equal({}, h)
  end

  def test_replace2
    h1 = @cls.new { :foo }
    h2 = @cls.new
    h2.replace h1
    assert_equal(:foo, h2[0])

    assert_raise(ArgumentError) { h2.replace() }
    assert_raise(TypeError) { h2.replace(1) }
    h2.freeze
    assert_raise(ArgumentError) { h2.replace() }
    assert_raise(RuntimeError) { h2.replace(h1) }
    assert_raise(RuntimeError) { h2.replace(42) }
  end

  def test_size2
    assert_equal(0, @cls[].size)
  end

  def test_equal2
    assert_not_equal(0, @cls[])
    o = Object.new
    o.instance_variable_set(:@cls, @cls)
    def o.to_hash; @cls[]; end
    def o.==(x); true; end
    assert_equal({}, o)
    def o.==(x); false; end
    assert_not_equal({}, o)

    h1 = @cls[1=>2]; h2 = @cls[3=>4]
    assert_not_equal(h1, h2)
    h1 = @cls[1=>2]; h2 = @cls[1=>4]
    assert_not_equal(h1, h2)
  end

  def test_eql
    assert_not_send([@cls[], :eql?, 0])
    o = Object.new
    o.instance_variable_set(:@cls, @cls)
    def o.to_hash; @cls[]; end
    def o.eql?(x); true; end
    assert_send([@cls[], :eql?, o])
    def o.eql?(x); false; end
    assert_not_send([@cls[], :eql?, o])
  end

  def test_hash2
    assert_kind_of(Integer, @cls[].hash)
    h = @cls[1=>2]
    h.shift
    assert_equal({}.hash, h.hash, '[ruby-core:38650]')
    bug9231 = '[ruby-core:58993] [Bug #9231]'
    assert_not_equal(0, @cls[].hash, bug9231)
  end

  def test_update2
    h1 = @cls[1=>2, 3=>4]
    h2 = {1=>3, 5=>7}
    h1.update(h2) {|k, v1, v2| k + v1 + v2 }
    assert_equal({1=>6, 3=>4, 5=>7}, h1)
  end

  def test_merge
    h1 = @cls[1=>2, 3=>4]
    h2 = {1=>3, 5=>7}
    assert_equal({1=>3, 3=>4, 5=>7}, h1.merge(h2))
    assert_equal({1=>6, 3=>4, 5=>7}, h1.merge(h2) {|k, v1, v2| k + v1 + v2 })
  end

  def test_assoc
    assert_equal([3,4], @cls[1=>2, 3=>4, 5=>6].assoc(3))
    assert_nil(@cls[1=>2, 3=>4, 5=>6].assoc(4))
    assert_equal([1.0,1], @cls[1.0=>1].assoc(1))
  end

  def test_assoc_compare_by_identity
    h = @cls[]
    h.compare_by_identity
    h["a"] = 1
    h["a".dup] = 2
    assert_equal(["a",1], h.assoc("a"))
  end

  def test_rassoc
    assert_equal([3,4], @cls[1=>2, 3=>4, 5=>6].rassoc(4))
    assert_nil({1=>2, 3=>4, 5=>6}.rassoc(3))
  end

  def test_flatten
    assert_equal([[1], [2]], @cls[[1] => [2]].flatten)

    a =  @cls[1=> "one", 2 => [2,"two"], 3 => [3, ["three"]]]
    assert_equal([1, "one", 2, [2, "two"], 3, [3, ["three"]]], a.flatten)
    assert_equal([[1, "one"], [2, [2, "two"]], [3, [3, ["three"]]]], a.flatten(0))
    assert_equal([1, "one", 2, [2, "two"], 3, [3, ["three"]]], a.flatten(1))
    assert_equal([1, "one", 2, 2, "two", 3, 3, ["three"]], a.flatten(2))
    assert_equal([1, "one", 2, 2, "two", 3, 3, "three"], a.flatten(3))
    assert_equal([1, "one", 2, 2, "two", 3, 3, "three"], a.flatten(-1))
    assert_raise(TypeError){ a.flatten(Object) }
  end

  def test_callcc
    h = @cls[1=>2]
    c = nil
    f = false
    h.each { callcc {|c2| c = c2 } }
    unless f
      f = true
      c.call
    end
    assert_raise(RuntimeError) { h.each { h.rehash } }

    h = @cls[1=>2]
    c = nil
    assert_raise(RuntimeError) do
      h.each { callcc {|c2| c = c2 } }
      h.clear
      c.call
    end
  end

  def test_callcc_iter_level
    bug9105 = '[ruby-dev:47803] [Bug #9105]'
    h = @cls[1=>2, 3=>4]
    c = nil
    f = false
    h.each {callcc {|c2| c = c2}}
    unless f
      f = true
      c.call
    end
    assert_nothing_raised(RuntimeError, bug9105) do
      h.each {|i, j|
        h.delete(i);
        assert_not_equal(false, i, bug9105)
      }
    end
  end

  def test_callcc_escape
    bug9105 = '[ruby-dev:47803] [Bug #9105]'
    assert_nothing_raised(RuntimeError, bug9105) do
      h=@cls[]
      cnt=0
      c = callcc {|cc|cc}
      h[cnt] = true
      h.each{|i|
        cnt+=1
        c.call if cnt == 1
      }
    end
  end

  def test_callcc_reenter
    bug9105 = '[ruby-dev:47803] [Bug #9105]'
    assert_nothing_raised(RuntimeError, bug9105) do
      h = @cls[1=>2,3=>4]
      c = nil
      f = false
      h.each { |i|
        callcc {|c2| c = c2 } unless c
        h.delete(1) if f
      }
      unless f
        f = true
        c.call
      end
    end
  end

  def test_threaded_iter_level
    bug9105 = '[ruby-dev:47807] [Bug #9105]'
    h = @cls[1=>2]
    2.times.map {
      f = false
      th = Thread.start {h.each {f = true; sleep}}
      Thread.pass until f
      Thread.pass until th.stop?
      th
    }.each {|th| th.run; th.join}
    assert_nothing_raised(RuntimeError, bug9105) do
      h[5] = 6
    end
    assert_equal(6, h[5], bug9105)
  end

  def test_compare_by_identity
    a = "foo"
    assert_not_predicate(@cls[], :compare_by_identity?)
    h = @cls[a => "bar"]
    assert_not_predicate(h, :compare_by_identity?)
    h.compare_by_identity
    assert_predicate(h, :compare_by_identity?)
    #assert_equal("bar", h[a])
    assert_nil(h["foo"])

    bug8703 = '[ruby-core:56256] [Bug #8703] copied identhash'
    h.clear
    assert_predicate(h.dup, :compare_by_identity?, bug8703)
  end

  def test_same_key
    bug9646 = '[ruby-dev:48047] [Bug #9646] Infinite loop at Hash#each'
    h = @cls[a=[], 1]
    a << 1
    h[[]] = 2
    a.clear
    cnt = 0
    r = h.each{ break nil if (cnt+=1) > 100 }
    assert_not_nil(r,bug9646)
  end

  class ObjWithHash
    def initialize(value, hash)
      @value = value
      @hash = hash
    end
    attr_reader :value, :hash

    def eql?(other)
      @value == other.value
    end
  end

  def test_hash_hash
    assert_equal({0=>2,11=>1}.hash, @cls[11=>1,0=>2].hash)
    o1 = ObjWithHash.new(0,1)
    o2 = ObjWithHash.new(11,1)
    assert_equal({o1=>1,o2=>2}.hash, @cls[o2=>2,o1=>1].hash)
  end

  def test_hash_bignum_hash
    x = 2<<(32-3)-1
    assert_equal({x=>1}.hash, @cls[x=>1].hash)
    x = 2<<(64-3)-1
    assert_equal({x=>1}.hash, @cls[x=>1].hash)

    o = Object.new
    def o.hash; 2 << 100; end
    assert_equal({o=>1}.hash, @cls[o=>1].hash)
  end

  def test_hash_popped
    assert_nothing_raised { eval("a = 1; @cls[a => a]; a") }
  end

  def test_recursive_key
    h = @cls[]
    assert_nothing_raised { h[h] = :foo }
    h.rehash
    assert_equal(:foo, h[h])
  end

  def test_inverse_hash
    feature4262 = '[ruby-core:34334]'
    [@cls[1=>2], @cls[123=>"abc"]].each do |h|
      assert_not_equal(h.hash, h.invert.hash, feature4262)
    end
  end

  def test_recursive_hash_value_struct
    bug9151 = '[ruby-core:58567] [Bug #9151]'

    s = Struct.new(:x) {def hash; [x,""].hash; end}
    a = s.new
    b = s.new
    a.x = b
    b.x = a
    assert_nothing_raised(SystemStackError, bug9151) {a.hash}
    assert_nothing_raised(SystemStackError, bug9151) {b.hash}

    h = @cls[]
    h[[a,"hello"]] = 1
    assert_equal(1, h.size)
    h[[b,"world"]] = 2
    assert_equal(2, h.size)

    obj = Object.new
    h = @cls[a => obj]
    assert_same(obj, h[b])
  end

  def test_recursive_hash_value_array
    h = @cls[]
    h[[[1]]] = 1
    assert_equal(1, h.size)
    h[[[2]]] = 1
    assert_equal(2, h.size)

    a = []
    a << a

    h = @cls[]
    h[[a, 1]] = 1
    assert_equal(1, h.size)
    h[[a, 2]] = 2
    assert_equal(2, h.size)
    h[[a, a]] = 3
    assert_equal(3, h.size)

    obj = Object.new
    h = @cls[a => obj]
    assert_same(obj, h[[[a]]])
  end

  def test_recursive_hash_value_array_hash
    h = @cls[]
    rec = [h]
    h[:x] = rec

    obj = Object.new
    h2 = {rec => obj}
    [h, {x: rec}].each do |k|
      k = [k]
      assert_same(obj, h2[k], ->{k.inspect})
    end
  end

  def test_recursive_hash_value_hash_array
    h = @cls[]
    rec = [h]
    h[:x] = rec

    obj = Object.new
    h2 = {h => obj}
    [rec, [h]].each do |k|
      k = {x: k}
      assert_same(obj, h2[k], ->{k.inspect})
    end
  end

  def test_exception_in_rehash_memory_leak
    return unless @cls == Hash

    bug9187 = '[ruby-core:58728] [Bug #9187]'

    prepare = <<-EOS
    class Foo
      def initialize
        @raise = false
      end

      def hash
        raise if @raise
        @raise = true
        return 0
      end
    end
    h = {Foo.new => true}
    EOS

    code = <<-EOS
    10_0000.times do
      h.rehash rescue nil
    end
    GC.start
    EOS

    assert_no_memory_leak([], prepare, code, bug9187)
  end

  def test_wrapper
    bug9381 = '[ruby-core:59638] [Bug #9381]'

    wrapper = Class.new do
      def initialize(obj)
        @obj = obj
      end

      def hash
        @obj.hash
      end

      def eql?(other)
        @obj.eql?(other)
      end
    end

    bad = [
      5, true, false, nil,
      0.0, 1.72723e-77,
      :foo, "dsym_#{self.object_id.to_s(16)}_#{Time.now.to_i.to_s(16)}".to_sym,
      "str",
    ].select do |x|
      hash = {x => bug9381}
      hash[wrapper.new(x)] != bug9381
    end
    assert_empty(bad, bug9381)
  end

  def assert_hash_random(obj, dump = obj.inspect)
    a = [obj.hash.to_s]
    3.times {
      assert_in_out_err(["-e", "print (#{dump}).hash"], "") do |r, e|
        a += r
        assert_equal([], e)
      end
    }
    assert_not_equal([obj.hash.to_s], a.uniq)
    assert_operator(a.uniq.size, :>, 2, proc {a.inspect})
  end

  def test_string_hash_random
    assert_hash_random('abc')
  end

  def test_symbol_hash_random
    assert_hash_random(:-)
    assert_hash_random(:foo)
    assert_hash_random("dsym_#{self.object_id.to_s(16)}_#{Time.now.to_i.to_s(16)}".to_sym)
  end

  def test_integer_hash_random
    assert_hash_random(0)
    assert_hash_random(+1)
    assert_hash_random(-1)
    assert_hash_random(+(1<<100))
    assert_hash_random(-(1<<100))
  end

  def test_float_hash_random
    assert_hash_random(0.0)
    assert_hash_random(+1.0)
    assert_hash_random(-1.0)
    assert_hash_random(1.72723e-77)
    assert_hash_random(Float::INFINITY, "Float::INFINITY")
  end

  def test_label_syntax
    return unless @cls == Hash

    feature4935 = '[ruby-core:37553] [Feature #4935]'
    x = 'world'
    hash = assert_nothing_raised(SyntaxError, feature4935) do
      break eval(%q({foo: 1, "foo-bar": 2, "hello-#{x}": 3, 'hello-#{x}': 4, 'bar': {}}))
    end
    assert_equal({:foo => 1, :'foo-bar' => 2, :'hello-world' => 3, :'hello-#{x}' => 4, :bar => {}}, hash, feature4935)
    x = x
  end

  def test_dig
    h = @cls[a: @cls[b: [1, 2, 3]], c: 4]
    assert_equal(1, h.dig(:a, :b, 0))
    assert_nil(h.dig(:b, 1))
    assert_raise(TypeError) {h.dig(:c, 1)}
    o = Object.new
    def o.dig(*args)
      {dug: args}
    end
    h[:d] = o
    assert_equal({dug: [:foo, :bar]}, h.dig(:d, :foo, :bar))
  end

  def test_dig_with_respond_to
    bug12030 = '[ruby-core:73556] [Bug #12030]'
    o = Object.new
    def o.respond_to?(*args)
      super
    end
    assert_raise(TypeError, bug12030) {{foo: o}.dig(:foo, :foo)}
  end

  def test_cmp
    h1 = {a:1, b:2}
    h2 = {a:1, b:2, c:3}

    assert_operator(h1, :<=, h1)
    assert_operator(h1, :<=, h2)
    assert_not_operator(h2, :<=, h1)
    assert_operator(h2, :<=, h2)

    assert_operator(h1, :>=, h1)
    assert_not_operator(h1, :>=, h2)
    assert_operator(h2, :>=, h1)
    assert_operator(h2, :>=, h2)

    assert_not_operator(h1, :<, h1)
    assert_operator(h1, :<, h2)
    assert_not_operator(h2, :<, h1)
    assert_not_operator(h2, :<, h2)

    assert_not_operator(h1, :>, h1)
    assert_not_operator(h1, :>, h2)
    assert_operator(h2, :>, h1)
    assert_not_operator(h2, :>, h2)
  end

  def test_cmp_samekeys
    h1 = {a:1}
    h2 = {a:2}

    assert_operator(h1, :<=, h1)
    assert_not_operator(h1, :<=, h2)
    assert_not_operator(h2, :<=, h1)
    assert_operator(h2, :<=, h2)

    assert_operator(h1, :>=, h1)
    assert_not_operator(h1, :>=, h2)
    assert_not_operator(h2, :>=, h1)
    assert_operator(h2, :>=, h2)

    assert_not_operator(h1, :<, h1)
    assert_not_operator(h1, :<, h2)
    assert_not_operator(h2, :<, h1)
    assert_not_operator(h2, :<, h2)

    assert_not_operator(h1, :>, h1)
    assert_not_operator(h1, :>, h2)
    assert_not_operator(h2, :>, h1)
    assert_not_operator(h2, :>, h2)
  end

  def test_to_proc
    h = {
      1 => 10,
      2 => 20,
      3 => 30,
    }

    assert_equal([10, 20, 30], [1, 2, 3].map(&h))
  end

  def test_transform_values
    x = @cls[a: 1, b: 2, c: 3]
    y = x.transform_values {|v| v ** 2 }
    assert_equal([1, 4, 9], y.values_at(:a, :b, :c))
    assert_not_same(x, y)

    y = x.transform_values.with_index {|v, i| "#{v}.#{i}" }
    assert_equal(%w(1.0  2.1  3.2), y.values_at(:a, :b, :c))
  end

  def test_transform_values_bang
    x = @cls[a: 1, b: 2, c: 3]
    y = x.transform_values! {|v| v ** 2 }
    assert_equal([1, 4, 9], y.values_at(:a, :b, :c))
    assert_same(x, y)

    x = @cls[a: 1, b: 2, c: 3]
    y = x.transform_values!.with_index {|v, i| "#{v}.#{i}" }
    assert_equal(%w(1.0  2.1  3.2), y.values_at(:a, :b, :c))
  end

  def test_broken_hash_value
    bug14218 = '[ruby-core:84395] [Bug #14218]'

    assert_equal(0, 1_000_000.times.count{a=Object.new.hash; b=Object.new.hash; a < 0 && b < 0 && a + b > 0}, bug14218)
    assert_equal(0, 1_000_000.times.count{a=Object.new.hash; b=Object.new.hash; 0 + a + b != 0 + b + a}, bug14218)
  end

  class TestSubHash < TestHash
    class SubHash < Hash
      def reject(*)
        super
      end
    end

    def setup
      @cls = SubHash
      super
    end
  end
end
