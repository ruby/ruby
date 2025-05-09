# frozen_string_literal: false
require 'test/unit'

class TestEnv < Test::Unit::TestCase
  windows = /bccwin|mswin|mingw/ =~ RUBY_PLATFORM
  IGNORE_CASE = windows
  ENCODING = windows ? Encoding::UTF_8 : Encoding.find("locale")
  PATH_ENV = "PATH"
  INVALID_ENVVARS = [
    "foo\0bar",
    "\xa1\xa1".force_encoding(Encoding::UTF_16LE),
    "foo".force_encoding(Encoding::ISO_2022_JP),
  ]

  def assert_invalid_env(msg = nil)
    all_assertions(msg) do |a|
      INVALID_ENVVARS.each do |v|
        a.for(v) do
          assert_raise(ArgumentError) {yield v}
        end
      end
    end
  end

  def setup
    @verbose = $VERBOSE
    @backup = ENV.to_hash
    ENV.delete('test')
    ENV.delete('TEST')
  end

  def teardown
    $VERBOSE = @verbose
    ENV.clear
    @backup.each {|k, v| ENV[k] = v }
  end

  def test_bracket
    assert_nil(ENV['test'])
    assert_nil(ENV['TEST'])
    ENV['test'] = 'foo'
    assert_equal('foo', ENV['test'])
    if IGNORE_CASE
      assert_equal('foo', ENV['TEST'])
    else
      assert_nil(ENV['TEST'])
    end
    ENV['TEST'] = 'bar'
    assert_equal('bar', ENV['TEST'])
    if IGNORE_CASE
      assert_equal('bar', ENV['test'])
    else
      assert_equal('foo', ENV['test'])
    end

    assert_raise(TypeError) {
      ENV[1]
    }
    assert_raise(TypeError) {
      ENV[1] = 'foo'
    }
    assert_raise(TypeError) {
      ENV['test'] = 0
    }
  end

  def test_dup
    assert_raise(TypeError) {
      ENV.dup
    }
  end

  def test_clone
    message = /Cannot clone ENV/
    assert_raise_with_message(TypeError, message) {
      ENV.clone
    }
    assert_raise_with_message(TypeError, message) {
      ENV.clone(freeze: false)
    }
    assert_raise_with_message(TypeError, message) {
      ENV.clone(freeze: nil)
    }
    assert_raise_with_message(TypeError, message) {
      ENV.clone(freeze: true)
    }

    assert_raise(ArgumentError) {
      ENV.clone(freeze: 1)
    }
    assert_raise(ArgumentError) {
      ENV.clone(foo: false)
    }
    assert_raise(ArgumentError) {
      ENV.clone(1)
    }
    assert_raise(ArgumentError) {
      ENV.clone(1, foo: false)
    }
  end

  def test_has_value
    val = 'a'
    val.succ! while ENV.has_value?(val) || ENV.has_value?(val.upcase)
    ENV['test'] = val[0...-1]

    assert_equal(false, ENV.has_value?(val))
    assert_equal(false, ENV.has_value?(val.upcase))
    ENV['test'] = val
    assert_equal(true, ENV.has_value?(val))
    assert_equal(false, ENV.has_value?(val.upcase))
    ENV['test'] = val.upcase
    assert_equal(false, ENV.has_value?(val))
    assert_equal(true, ENV.has_value?(val.upcase))
  end

  def test_key
    val = 'a'
    val.succ! while ENV.has_value?(val) || ENV.has_value?(val.upcase)
    ENV['test'] = val[0...-1]

    assert_nil(ENV.key(val))
    assert_nil(ENV.key(val.upcase))
    ENV['test'] = val
    if IGNORE_CASE
      assert_equal('TEST', ENV.key(val).upcase)
    else
      assert_equal('test', ENV.key(val))
    end
    assert_nil(ENV.key(val.upcase))
    ENV['test'] = val.upcase
    assert_nil(ENV.key(val))
    if IGNORE_CASE
      assert_equal('TEST', ENV.key(val.upcase).upcase)
    else
      assert_equal('test', ENV.key(val.upcase))
    end
  end

  def test_delete
    assert_invalid_env {|v| ENV.delete(v)}
    assert_nil(ENV.delete("TEST"))
    assert_nothing_raised { ENV.delete(PATH_ENV) }
    assert_equal("NO TEST", ENV.delete("TEST") {|name| "NO "+name})
  end

  def test_getenv
    assert_invalid_env {|v| ENV[v]}
    ENV[PATH_ENV] = ""
    assert_equal("", ENV[PATH_ENV])
    assert_nil(ENV[""])
  end

  def test_fetch
    ENV["test"] = "foo"
    assert_equal("foo", ENV.fetch("test"))
    ENV.delete("test")
    feature8649 = '[ruby-core:56062] [Feature #8649]'
    e = assert_raise_with_message(KeyError, /key not found: "test"/, feature8649) do
      ENV.fetch("test")
    end
    assert_same(ENV, e.receiver)
    assert_equal("test", e.key)
    assert_equal("foo", ENV.fetch("test", "foo"))
    assert_equal("bar", ENV.fetch("test") { "bar" })
    EnvUtil.suppress_warning do
      assert_equal("bar", ENV.fetch("test", "foo") { "bar" })
    end
    assert_invalid_env {|v| ENV.fetch(v)}
    assert_nothing_raised { ENV.fetch(PATH_ENV, "foo") }
    ENV[PATH_ENV] = ""
    assert_equal("", ENV.fetch(PATH_ENV))
  end

  def test_aset
    assert_nothing_raised { ENV["test"] = nil }
    assert_equal(nil, ENV["test"])
    assert_invalid_env {|v| ENV[v] = "test"}
    assert_invalid_env {|v| ENV["test"] = v}

    begin
      # setenv(3) allowed the name includes '=',
      # but POSIX.1-2001 says it should fail with EINVAL.
      # see also http://togetter.com/li/22380
      ENV["foo=bar"] = "test"
      assert_equal("test", ENV["foo=bar"])
      assert_equal("test", ENV["foo"])
    rescue Errno::EINVAL
    end
  end

  def test_keys
    a = ENV.keys
    assert_kind_of(Array, a)
    a.each {|k| assert_kind_of(String, k) }
  end

  def test_each_key
    ENV.each_key {|k| assert_kind_of(String, k) }
  end

  def test_values
    a = ENV.values
    assert_kind_of(Array, a)
    a.each {|k| assert_kind_of(String, k) }
  end

  def test_each_value
    ENV.each_value {|k| assert_kind_of(String, k) }
  end

  def test_each_pair
    ENV.each_pair do |k, v|
      assert_kind_of(String, k)
      assert_kind_of(String, v)
    end
  end

  def test_reject_bang
    h1 = {}
    ENV.each_pair {|k, v| h1[k] = v }
    ENV["test"] = "foo"
    ENV.reject! {|k, v| IGNORE_CASE ? k.upcase == "TEST" : k == "test" }
    h2 = {}
    ENV.each_pair {|k, v| h2[k] = v }
    assert_equal(h1, h2)

    assert_nil(ENV.reject! {|k, v| IGNORE_CASE ? k.upcase == "TEST" : k == "test" })
  end

  def test_delete_if
    h1 = {}
    ENV.each_pair {|k, v| h1[k] = v }
    ENV["test"] = "foo"
    ENV.delete_if {|k, v| IGNORE_CASE ? k.upcase == "TEST" : k == "test" }
    h2 = {}
    ENV.each_pair {|k, v| h2[k] = v }
    assert_equal(h1, h2)

    assert_equal(ENV, ENV.delete_if {|k, v| IGNORE_CASE ? k.upcase == "TEST" : k == "test" })
  end

  def test_select_bang
    h1 = {}
    ENV.each_pair {|k, v| h1[k] = v }
    ENV["test"] = "foo"
    ENV.select! {|k, v| IGNORE_CASE ? k.upcase != "TEST" : k != "test" }
    h2 = {}
    ENV.each_pair {|k, v| h2[k] = v }
    assert_equal(h1, h2)

    assert_nil(ENV.select! {|k, v| IGNORE_CASE ? k.upcase != "TEST" : k != "test" })
  end

  def test_filter_bang
    h1 = {}
    ENV.each_pair {|k, v| h1[k] = v }
    ENV["test"] = "foo"
    ENV.filter! {|k, v| IGNORE_CASE ? k.upcase != "TEST" : k != "test" }
    h2 = {}
    ENV.each_pair {|k, v| h2[k] = v }
    assert_equal(h1, h2)

    assert_nil(ENV.filter! {|k, v| IGNORE_CASE ? k.upcase != "TEST" : k != "test" })
  end

  def test_keep_if
    h1 = {}
    ENV.each_pair {|k, v| h1[k] = v }
    ENV["test"] = "foo"
    ENV.keep_if {|k, v| IGNORE_CASE ? k.upcase != "TEST" : k != "test" }
    h2 = {}
    ENV.each_pair {|k, v| h2[k] = v }
    assert_equal(h1, h2)

    assert_equal(ENV, ENV.keep_if {|k, v| IGNORE_CASE ? k.upcase != "TEST" : k != "test" })
  end

  def test_values_at
    ENV["test"] = "foo"
    assert_equal(["foo", "foo"], ENV.values_at("test", "test"))
  end

  def test_select
    ENV["test"] = "foo"
    h = ENV.select {|k| IGNORE_CASE ? k.upcase == "TEST" : k == "test" }
    assert_equal(1, h.size)
    k = h.keys.first
    v = h.values.first
    if IGNORE_CASE
      assert_equal("TEST", k.upcase)
      assert_equal("FOO", v.upcase)
    else
      assert_equal("test", k)
      assert_equal("foo", v)
    end
  end

  def test_filter
    ENV["test"] = "foo"
    h = ENV.filter {|k| IGNORE_CASE ? k.upcase == "TEST" : k == "test" }
    assert_equal(1, h.size)
    k = h.keys.first
    v = h.values.first
    if IGNORE_CASE
      assert_equal("TEST", k.upcase)
      assert_equal("FOO", v.upcase)
    else
      assert_equal("test", k)
      assert_equal("foo", v)
    end
  end

  def test_slice
    ENV.clear
    ENV["foo"] = "bar"
    ENV["baz"] = "qux"
    ENV["bar"] = "rab"
    assert_equal({}, ENV.slice())
    assert_equal({}, ENV.slice(""))
    assert_equal({}, ENV.slice("unknown"))
    assert_equal({"foo"=>"bar", "baz"=>"qux"}, ENV.slice("foo", "baz"))
  end

  def test_except
    ENV.clear
    ENV["foo"] = "bar"
    ENV["baz"] = "qux"
    ENV["bar"] = "rab"
    assert_equal({"bar"=>"rab", "baz"=>"qux", "foo"=>"bar"}, ENV.except())
    assert_equal({"bar"=>"rab", "baz"=>"qux", "foo"=>"bar"}, ENV.except(""))
    assert_equal({"bar"=>"rab", "baz"=>"qux", "foo"=>"bar"}, ENV.except("unknown"))
    assert_equal({"bar"=>"rab"}, ENV.except("foo", "baz"))
  end

  def test_clear
    ENV.clear
    assert_equal(0, ENV.size)
  end

  def test_to_s
    assert_equal("ENV", ENV.to_s)
  end

  def test_inspect
    ENV.clear
    ENV["foo"] = "bar"
    ENV["baz"] = "qux"
    s = ENV.inspect
    expected = [%("foo" => "bar"), %("baz" => "qux")]
    unless s.start_with?(/\{"foo"/i)
      expected.reverse!
    end
    expected = '{' + expected.join(', ') + '}'
    if IGNORE_CASE
      s = s.upcase
      expected = expected.upcase
    end
    assert_equal(expected, s)
  end

  def test_inspect_encoding
    ENV.clear
    key = "VAR\u{e5 e1 e2 e4 e3 101 3042}"
    ENV[key] = "foo"
    assert_equal(%{{#{(key.encode(ENCODING) rescue key.b).inspect} => "foo"}}, ENV.inspect)
  end

  def test_to_a
    ENV.clear
    ENV["foo"] = "bar"
    ENV["baz"] = "qux"
    a = ENV.to_a
    assert_equal(2, a.size)
    check([%w(baz qux), %w(foo bar)], a)
  end

  def test_rehash
    assert_nil(ENV.rehash)
  end

  def test_size
    s = ENV.size
    ENV["test"] = "foo"
    assert_equal(s + 1, ENV.size)
  end

  def test_empty_p
    ENV.clear
    assert_predicate(ENV, :empty?)
    ENV["test"] = "foo"
    assert_not_predicate(ENV, :empty?)
  end

  def test_has_key
    assert_not_send([ENV, :has_key?, "test"])
    ENV["test"] = "foo"
    assert_send([ENV, :has_key?, "test"])
    assert_invalid_env {|v| ENV.has_key?(v)}
  end

  def test_assoc
    assert_nil(ENV.assoc("test"))
    ENV["test"] = "foo"
    k, v = ENV.assoc("test")
    if IGNORE_CASE
      assert_equal("TEST", k.upcase)
      assert_equal("FOO", v.upcase)
    else
      assert_equal("test", k)
      assert_equal("foo", v)
    end
    assert_invalid_env {|var| ENV.assoc(var)}
    assert_equal(ENCODING, v.encoding)
  end

  def test_has_value2
    ENV.clear
    assert_not_send([ENV, :has_value?, "foo"])
    ENV["test"] = "foo"
    assert_send([ENV, :has_value?, "foo"])
  end

  def test_rassoc
    ENV.clear
    assert_nil(ENV.rassoc("foo"))
    ENV["foo"] = "bar"
    ENV["test"] = "foo"
    ENV["baz"] = "qux"
    k, v = ENV.rassoc("foo")
    if IGNORE_CASE
      assert_equal("TEST", k.upcase)
      assert_equal("FOO", v.upcase)
    else
      assert_equal("test", k)
      assert_equal("foo", v)
    end
  end

  def test_to_hash
    h = {}
    ENV.each {|k, v| h[k] = v }
    assert_equal(h, ENV.to_hash)
  end

  def test_to_h
    assert_equal(ENV.to_hash, ENV.to_h)
    assert_equal(ENV.map {|k, v| ["$#{k}", v.size]}.to_h,
                 ENV.to_h {|k, v| ["$#{k}", v.size]})
  end

  def test_reject
    h1 = {}
    ENV.each_pair {|k, v| h1[k] = v }
    ENV["test"] = "foo"
    h2 = ENV.reject {|k, v| IGNORE_CASE ? k.upcase == "TEST" : k == "test" }
    assert_equal(h1, h2)
  end

  def assert_equal_env(as, bs)
    if IGNORE_CASE
      as = as.map {|k, v| [k.upcase, v] }
      bs = bs.map {|k, v| [k.upcase, v] }
    end
    assert_equal(as.sort, bs.sort)
  end
  alias check assert_equal_env

  def test_shift
    ENV.clear
    ENV["foo"] = "bar"
    ENV["baz"] = "qux"
    a = ENV.shift
    b = ENV.shift
    check([a, b], [%w(foo bar), %w(baz qux)])
    assert_nil(ENV.shift)
  end

  def test_invert
    ENV.clear
    ENV["foo"] = "bar"
    ENV["baz"] = "qux"
    check(ENV.invert.to_a, [%w(bar foo), %w(qux baz)])
  end

  def test_replace
    ENV["foo"] = "xxx"
    ENV.replace({"foo"=>"bar", "baz"=>"qux"})
    check(ENV.to_hash.to_a, [%w(foo bar), %w(baz qux)])
    ENV.replace({"Foo"=>"Bar", "Baz"=>"Qux"})
    check(ENV.to_hash.to_a, [%w(Foo Bar), %w(Baz Qux)])
  end

  def test_update
    ENV.clear
    ENV["foo"] = "bar"
    ENV["baz"] = "qux"
    ENV.update({"baz"=>"quux","a"=>"b"})
    check(ENV.to_hash.to_a, [%w(foo bar), %w(baz quux), %w(a b)])
    ENV.update
    check(ENV.to_hash.to_a, [%w(foo bar), %w(baz quux), %w(a b)])
    ENV.update({"foo"=>"zot"}, {"c"=>"d"})
    check(ENV.to_hash.to_a, [%w(foo zot), %w(baz quux), %w(a b), %w(c d)])

    ENV.clear
    ENV["foo"] = "bar"
    ENV["baz"] = "qux"
    ENV.update({"baz"=>"quux","a"=>"b"}) {|k, v1, v2| k + "_" + v1 + "_" + v2 }
    check(ENV.to_hash.to_a, [%w(foo bar), %w(baz baz_qux_quux), %w(a b)])
    ENV.update {|k, v1, v2| k + "_" + v1 + "_" + v2 }
    check(ENV.to_hash.to_a, [%w(foo bar), %w(baz baz_qux_quux), %w(a b)])
    ENV.update({"foo"=>"zot"}, {"c"=>"d"}) {|k, v1, v2| k + "_" + v1 + "_" + v2 }
    check(ENV.to_hash.to_a, [%w(foo foo_bar_zot), %w(baz baz_qux_quux), %w(a b), %w(c d)])
  end

  def test_huge_value
    if /mswin|ucrt/ =~ RUBY_PLATFORM
      # On Windows >= Vista each environment variable can be max 32768 characters
      huge_value = "bar" * 10900
    else
      huge_value = "bar" * 40960
    end
    ENV["foo"] = "overwritten"
    assert_nothing_raised { ENV["foo"] = huge_value }
    assert_equal(huge_value, ENV["foo"])
  end

  if windows
    def windows_version
      @windows_version ||= %x[ver][/Version (\d+)/, 1].to_i
    end

    def test_win32_blocksize
      keys = []
      len = 32767 - ENV.to_a.flatten.inject(1) {|r,e| r + e.bytesize + 1}
      val = "bar" * 1000
      key = nil
      while (len -= val.size + (key="foo#{len}").size + 2) > 0
        keys << key
        ENV[key] = val
      end
      if windows_version < 6
        1.upto(12) {|i|
          assert_raise(Errno::EINVAL) { ENV[key] = val }
        }
      else
        1.upto(12) {|i|
          assert_nothing_raised(Errno::EINVAL) { ENV[key] = val }
        }
      end
    ensure
      keys.each {|k| ENV.delete(k)}
    end
  end

  def test_frozen_env
    assert_raise(TypeError) { ENV.freeze }
  end

  def test_frozen
    ENV[PATH_ENV] = "/"
    ENV.each do |k, v|
      assert_predicate(k, :frozen?)
      assert_predicate(v, :frozen?)
    end
    ENV.each_key do |k|
      assert_predicate(k, :frozen?)
    end
    ENV.each_value do |v|
      assert_predicate(v, :frozen?)
    end
    ENV.each_key do |k|
      assert_predicate(ENV[k], :frozen?, "[#{k.dump}]")
      assert_predicate(ENV.fetch(k), :frozen?, "fetch(#{k.dump})")
    end
  end

  def test_shared_substring
    bug12475 = '[ruby-dev:49655] [Bug #12475]'
    n = [*"0".."9"].join("")*3
    e0 = ENV[n0 = "E#{n}"]
    e1 = ENV[n1 = "E#{n}."]
    ENV[n0] = nil
    ENV[n1] = nil
    ENV[n1.chop] = "T#{n}.".chop
    ENV[n0], e0 = e0, ENV[n0]
    ENV[n1], e1 = e1, ENV[n1]
    assert_equal("T#{n}", e0, bug12475)
    assert_nil(e1, bug12475)
  end

  def ignore_case_str
    IGNORE_CASE ? "true" : "false"
  end

  def str_for_yielding_exception_class(code_str, exception_var: "raised_exception")
    <<-"end;"
      #{exception_var} = nil
      begin
        #{code_str}
      rescue Exception => e
        #{exception_var} = e
      end
      Ractor.yield #{exception_var}.class
    end;
  end

  def str_for_assert_raise_on_yielded_exception_class(expected_error_class, ractor_var)
    <<-"end;"
      error_class = #{ractor_var}.take
      assert_raise(#{expected_error_class}) do
        if error_class < Exception
          raise error_class
        end
      end
    end;
  end

  def str_to_yield_invalid_envvar_errors(var_name, code_str)
    <<-"end;"
      envvars_to_check = [
        "foo\0bar",
        "#{'\xa1\xa1'}".dup.force_encoding(Encoding::UTF_16LE),
        "foo".dup.force_encoding(Encoding::ISO_2022_JP),
      ]
      envvars_to_check.each do |#{var_name}|
        #{str_for_yielding_exception_class(code_str)}
      end
    end;
  end

  def str_to_receive_invalid_envvar_errors(ractor_var)
    <<-"end;"
      3.times do
        #{str_for_assert_raise_on_yielded_exception_class(ArgumentError, ractor_var)}
      end
    end;
  end

  STR_DEFINITION_FOR_CHECK = %Q{
      def check(as, bs)
        if #{IGNORE_CASE ? "true" : "false"}
          as = as.map {|k, v| [k.upcase, v] }
          bs = bs.map {|k, v| [k.upcase, v] }
        end
        assert_equal(as.sort, bs.sort)
      end
  }

  def test_bracket_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        Ractor.yield ENV['test']
        Ractor.yield ENV['TEST']
        ENV['test'] = 'foo'
        Ractor.yield ENV['test']
        Ractor.yield ENV['TEST']
        ENV['TEST'] = 'bar'
        Ractor.yield ENV['TEST']
        Ractor.yield ENV['test']
        #{str_for_yielding_exception_class("ENV[1]")}
        #{str_for_yielding_exception_class("ENV[1] = 'foo'")}
        #{str_for_yielding_exception_class("ENV['test'] = 0")}
      end
      assert_nil(r.take)
      assert_nil(r.take)
      assert_equal('foo', r.take)
      if #{ignore_case_str}
        assert_equal('foo', r.take)
      else
        assert_nil(r.take)
      end
      assert_equal('bar', r.take)
      if #{ignore_case_str}
        assert_equal('bar', r.take)
      else
        assert_equal('foo', r.take)
      end
      3.times do
        #{str_for_assert_raise_on_yielded_exception_class(TypeError, "r")}
      end
    end;
  end

  def test_dup_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        #{str_for_yielding_exception_class("ENV.dup")}
      end
      #{str_for_assert_raise_on_yielded_exception_class(TypeError, "r")}
    end;
  end

  def test_has_value_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        val = 'a'
        val.succ! while ENV.has_value?(val) || ENV.has_value?(val.upcase)
        ENV['test'] = val[0...-1]
        Ractor.yield(ENV.has_value?(val))
        Ractor.yield(ENV.has_value?(val.upcase))
        ENV['test'] = val
        Ractor.yield(ENV.has_value?(val))
        Ractor.yield(ENV.has_value?(val.upcase))
        ENV['test'] = val.upcase
        Ractor.yield ENV.has_value?(val)
        Ractor.yield ENV.has_value?(val.upcase)
      end
      assert_equal(false, r.take)
      assert_equal(false, r.take)
      assert_equal(true, r.take)
      assert_equal(false, r.take)
      assert_equal(false, r.take)
      assert_equal(true, r.take)
    end;
  end

  def test_key_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        val = 'a'
        val.succ! while ENV.has_value?(val) || ENV.has_value?(val.upcase)
        ENV['test'] = val[0...-1]
        Ractor.yield ENV.key(val)
        Ractor.yield ENV.key(val.upcase)
        ENV['test'] = val
        Ractor.yield ENV.key(val)
        Ractor.yield ENV.key(val.upcase)
        ENV['test'] = val.upcase
        Ractor.yield ENV.key(val)
        Ractor.yield ENV.key(val.upcase)
      end
      assert_nil(r.take)
      assert_nil(r.take)
      if #{ignore_case_str}
        assert_equal('TEST', r.take.upcase)
      else
        assert_equal('test', r.take)
      end
      assert_nil(r.take)
      assert_nil(r.take)
      if #{ignore_case_str}
        assert_equal('TEST', r.take.upcase)
      else
        assert_equal('test', r.take)
      end
    end;

  end

  def test_delete_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        #{str_to_yield_invalid_envvar_errors("v", "ENV.delete(v)")}
        Ractor.yield ENV.delete("TEST")
        #{str_for_yielding_exception_class("ENV.delete('#{PATH_ENV}')")}
        Ractor.yield(ENV.delete("TEST"){|name| "NO "+name})
      end
      #{str_to_receive_invalid_envvar_errors("r")}
      assert_nil(r.take)
      exception_class = r.take
      assert_equal(NilClass, exception_class)
      assert_equal("NO TEST", r.take)
    end;
  end

  def test_getenv_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        #{str_to_yield_invalid_envvar_errors("v", "ENV[v]")}
        ENV["#{PATH_ENV}"] = ""
        Ractor.yield ENV["#{PATH_ENV}"]
        Ractor.yield ENV[""]
      end
      #{str_to_receive_invalid_envvar_errors("r")}
      assert_equal("", r.take)
      assert_nil(r.take)
    end;
  end

  def test_fetch_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        ENV["test"] = "foo"
        Ractor.yield ENV.fetch("test")
        ENV.delete("test")
        #{str_for_yielding_exception_class("ENV.fetch('test')", exception_var: "ex")}
        Ractor.yield ex.receiver.object_id
        Ractor.yield ex.key
        Ractor.yield ENV.fetch("test", "foo")
        Ractor.yield(ENV.fetch("test"){"bar"})
        #{str_to_yield_invalid_envvar_errors("v", "ENV.fetch(v)")}
        #{str_for_yielding_exception_class("ENV.fetch('#{PATH_ENV}', 'foo')")}
        ENV['#{PATH_ENV}'] = ""
        Ractor.yield ENV.fetch('#{PATH_ENV}')
      end
      assert_equal("foo", r.take)
      #{str_for_assert_raise_on_yielded_exception_class(KeyError, "r")}
      assert_equal(ENV.object_id, r.take)
      assert_equal("test", r.take)
      assert_equal("foo", r.take)
      assert_equal("bar", r.take)
      #{str_to_receive_invalid_envvar_errors("r")}
      exception_class = r.take
      assert_equal(NilClass, exception_class)
      assert_equal("", r.take)
    end;
  end

  def test_aset_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        #{str_for_yielding_exception_class("ENV['test'] = nil")}
        ENV["test"] = nil
        Ractor.yield ENV["test"]
        #{str_to_yield_invalid_envvar_errors("v", "ENV[v] = 'test'")}
        #{str_to_yield_invalid_envvar_errors("v", "ENV['test'] = v")}
      end
      exception_class = r.take
      assert_equal(NilClass, exception_class)
      assert_nil(r.take)
      #{str_to_receive_invalid_envvar_errors("r")}
      #{str_to_receive_invalid_envvar_errors("r")}
    end;
  end

  def test_keys_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        a = ENV.keys
        Ractor.yield a
      end
      a = r.take
      assert_kind_of(Array, a)
      a.each {|k| assert_kind_of(String, k) }
    end;

  end

  def test_each_key_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        ENV.each_key {|k| Ractor.yield(k)}
        Ractor.yield "finished"
      end
      while((x=r.take) != "finished")
        assert_kind_of(String, x)
      end
    end;
  end

  def test_values_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        a = ENV.values
        Ractor.yield a
      end
      a = r.take
      assert_kind_of(Array, a)
      a.each {|k| assert_kind_of(String, k) }
    end;
  end

  def test_each_value_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        ENV.each_value {|k| Ractor.yield(k)}
        Ractor.yield "finished"
      end
      while((x=r.take) != "finished")
        assert_kind_of(String, x)
      end
    end;
  end

  def test_each_pair_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        ENV.each_pair {|k, v| Ractor.yield([k,v])}
        Ractor.yield "finished"
      end
      while((k,v=r.take) != "finished")
        assert_kind_of(String, k)
        assert_kind_of(String, v)
      end
    end;
  end

  def test_reject_bang_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        h1 = {}
        ENV.each_pair {|k, v| h1[k] = v }
        ENV["test"] = "foo"
        ENV.reject! {|k, v| #{ignore_case_str} ? k.upcase == "TEST" : k == "test" }
        h2 = {}
        ENV.each_pair {|k, v| h2[k] = v }
        Ractor.yield [h1, h2]
        Ractor.yield(ENV.reject! {|k, v| #{ignore_case_str} ? k.upcase == "TEST" : k == "test" })
      end
      h1, h2 = r.take
      assert_equal(h1, h2)
      assert_nil(r.take)
    end;
  end

  def test_delete_if_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        h1 = {}
        ENV.each_pair {|k, v| h1[k] = v }
        ENV["test"] = "foo"
        ENV.delete_if {|k, v| #{ignore_case_str} ? k.upcase == "TEST" : k == "test" }
        h2 = {}
        ENV.each_pair {|k, v| h2[k] = v }
        Ractor.yield [h1, h2]
        Ractor.yield (ENV.delete_if {|k, v| #{ignore_case_str} ? k.upcase == "TEST" : k == "test" })
      end
      h1, h2 = r.take
      assert_equal(h1, h2)
      assert_same(ENV, r.take)
    end;
  end

  def test_select_bang_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        h1 = {}
        ENV.each_pair {|k, v| h1[k] = v }
        ENV["test"] = "foo"
        ENV.select! {|k, v| #{ignore_case_str} ? k.upcase != "TEST" : k != "test" }
        h2 = {}
        ENV.each_pair {|k, v| h2[k] = v }
        Ractor.yield [h1, h2]
        Ractor.yield(ENV.select! {|k, v| #{ignore_case_str} ? k.upcase != "TEST" : k != "test" })
      end
      h1, h2 = r.take
      assert_equal(h1, h2)
      assert_nil(r.take)
    end;
  end

  def test_filter_bang_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        h1 = {}
        ENV.each_pair {|k, v| h1[k] = v }
        ENV["test"] = "foo"
        ENV.filter! {|k, v| #{ignore_case_str} ? k.upcase != "TEST" : k != "test" }
        h2 = {}
        ENV.each_pair {|k, v| h2[k] = v }
        Ractor.yield [h1, h2]
        Ractor.yield(ENV.filter! {|k, v| #{ignore_case_str} ? k.upcase != "TEST" : k != "test" })
      end
      h1, h2 = r.take
      assert_equal(h1, h2)
      assert_nil(r.take)
    end;
  end

  def test_keep_if_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        h1 = {}
        ENV.each_pair {|k, v| h1[k] = v }
        ENV["test"] = "foo"
        ENV.keep_if {|k, v| #{ignore_case_str} ? k.upcase != "TEST" : k != "test" }
        h2 = {}
        ENV.each_pair {|k, v| h2[k] = v }
        Ractor.yield [h1, h2]
        Ractor.yield (ENV.keep_if {|k, v| #{ignore_case_str} ? k.upcase != "TEST" : k != "test" })
      end
      h1, h2 = r.take
      assert_equal(h1, h2)
      assert_equal(ENV, r.take)
    end;
  end

  def test_values_at_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        ENV["test"] = "foo"
        Ractor.yield ENV.values_at("test", "test")
      end
      assert_equal(["foo", "foo"], r.take)
    end;
  end

  def test_select_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        ENV["test"] = "foo"
        h = ENV.select {|k| #{ignore_case_str} ? k.upcase == "TEST" : k == "test" }
        Ractor.yield h.size
        k = h.keys.first
        v = h.values.first
        Ractor.yield [k, v]
      end
      assert_equal(1, r.take)
      k, v = r.take
      if #{ignore_case_str}
        assert_equal("TEST", k.upcase)
        assert_equal("FOO", v.upcase)
      else
        assert_equal("test", k)
        assert_equal("foo", v)
      end
    end;
  end

  def test_filter_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        ENV["test"] = "foo"
        h = ENV.filter {|k| #{ignore_case_str} ? k.upcase == "TEST" : k == "test" }
        Ractor.yield(h.size)
        k = h.keys.first
        v = h.values.first
        Ractor.yield [k, v]
      end
      assert_equal(1, r.take)
      k, v = r.take
      if #{ignore_case_str}
        assert_equal("TEST", k.upcase)
        assert_equal("FOO", v.upcase)
      else
        assert_equal("test", k)
        assert_equal("foo", v)
      end
    end;
  end

  def test_slice_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        ENV.clear
        ENV["foo"] = "bar"
        ENV["baz"] = "qux"
        ENV["bar"] = "rab"
        Ractor.yield(ENV.slice())
        Ractor.yield(ENV.slice(""))
        Ractor.yield(ENV.slice("unknown"))
        Ractor.yield(ENV.slice("foo", "baz"))
      end
      assert_equal({}, r.take)
      assert_equal({}, r.take)
      assert_equal({}, r.take)
      assert_equal({"foo"=>"bar", "baz"=>"qux"}, r.take)
    end;
  end

  def test_except_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        ENV.clear
        ENV["foo"] = "bar"
        ENV["baz"] = "qux"
        ENV["bar"] = "rab"
        Ractor.yield ENV.except()
        Ractor.yield ENV.except("")
        Ractor.yield ENV.except("unknown")
        Ractor.yield ENV.except("foo", "baz")
      end
      assert_equal({"bar"=>"rab", "baz"=>"qux", "foo"=>"bar"}, r.take)
      assert_equal({"bar"=>"rab", "baz"=>"qux", "foo"=>"bar"}, r.take)
      assert_equal({"bar"=>"rab", "baz"=>"qux", "foo"=>"bar"}, r.take)
      assert_equal({"bar"=>"rab"}, r.take)
    end;
  end

  def test_clear_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        ENV.clear
        Ractor.yield ENV.size
      end
      assert_equal(0, r.take)
    end;
  end

  def test_to_s_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        ENV.to_s
      end
      assert_equal("ENV", r.take)
    end;
  end

  def test_inspect_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        ENV.clear
        ENV["foo"] = "bar"
        ENV["baz"] = "qux"
        s = ENV.inspect
        Ractor.yield s
      end
      s = r.take
      expected = ['"foo" => "bar"', '"baz" => "qux"']
      unless s.start_with?(/\{"foo"/i)
        expected.reverse!
      end
      expected = "{" + expected.join(', ') + "}"
      if #{ignore_case_str}
        s = s.upcase
        expected = expected.upcase
      end
      assert_equal(expected, s)
    end;
  end

  def test_to_a_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        ENV.clear
        ENV["foo"] = "bar"
        ENV["baz"] = "qux"
        a = ENV.to_a
        Ractor.yield a
      end
      a = r.take
      assert_equal(2, a.size)
      expected = [%w(baz qux), %w(foo bar)]
      if #{ignore_case_str}
        a = a.map {|x, y| [x.upcase, y]}
        expected.map! {|x, y| [x.upcase, y]}
      end
      a.sort!
      assert_equal(expected, a)
    end;
  end

  def test_rehash_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        ENV.rehash
      end
      assert_nil(r.take)
    end;
  end

  def test_size_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        s = ENV.size
        ENV["test"] = "foo"
        Ractor.yield [s, ENV.size]
      end
      s, s2 = r.take
      assert_equal(s + 1, s2)
    end;
  end

  def test_empty_p_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        ENV.clear
        Ractor.yield ENV.empty?
        ENV["test"] = "foo"
        Ractor.yield ENV.empty?
      end
      assert r.take
      assert !r.take
    end;
  end

  def test_has_key_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        Ractor.yield ENV.has_key?("test")
        ENV["test"] = "foo"
        Ractor.yield ENV.has_key?("test")
        #{str_to_yield_invalid_envvar_errors("v", "ENV.has_key?(v)")}
      end
      assert !r.take
      assert r.take
      #{str_to_receive_invalid_envvar_errors("r")}
    end;
  end

  def test_assoc_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        Ractor.yield ENV.assoc("test")
        ENV["test"] = "foo"
        Ractor.yield ENV.assoc("test")
        #{str_to_yield_invalid_envvar_errors("v", "ENV.assoc(v)")}
      end
      assert_nil(r.take)
      k, v = r.take
      if #{ignore_case_str}
        assert_equal("TEST", k.upcase)
        assert_equal("FOO", v.upcase)
      else
        assert_equal("test", k)
        assert_equal("foo", v)
      end
      #{str_to_receive_invalid_envvar_errors("r")}
      encoding = /mswin|mingw/ =~ RUBY_PLATFORM ? Encoding::UTF_8 : Encoding.find("locale")
      assert_equal(encoding, v.encoding)
    end;
  end

  def test_has_value2_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        ENV.clear
        Ractor.yield ENV.has_value?("foo")
        ENV["test"] = "foo"
        Ractor.yield ENV.has_value?("foo")
      end
      assert !r.take
      assert r.take
    end;
  end

  def test_rassoc_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        ENV.clear
        Ractor.yield ENV.rassoc("foo")
        ENV["foo"] = "bar"
        ENV["test"] = "foo"
        ENV["baz"] = "qux"
        Ractor.yield ENV.rassoc("foo")
      end
      assert_nil(r.take)
      k, v = r.take
      if #{ignore_case_str}
        assert_equal("TEST", k.upcase)
        assert_equal("FOO", v.upcase)
      else
        assert_equal("test", k)
        assert_equal("foo", v)
      end
    end;
  end

  def test_to_hash_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        h = {}
        ENV.each {|k, v| h[k] = v }
        Ractor.yield [h, ENV.to_hash]
      end
      h, h2 = r.take
      assert_equal(h, h2)
    end;
  end

  def test_to_h_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        Ractor.yield [ENV.to_hash, ENV.to_h]
        Ractor.yield [ENV.map {|k, v| ["$\#{k}", v.size]}.to_h, ENV.to_h {|k, v| ["$\#{k}", v.size]}]
      end
      a, b = r.take
      assert_equal(a,b)
      c, d = r.take
      assert_equal(c,d)
    end;
  end

  def test_reject_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        h1 = {}
        ENV.each_pair {|k, v| h1[k] = v }
        ENV["test"] = "foo"
        h2 = ENV.reject {|k, v| #{ignore_case_str} ? k.upcase == "TEST" : k == "test" }
        Ractor.yield [h1, h2]
      end
      h1, h2 = r.take
      assert_equal(h1, h2)
    end;
  end

  def test_shift_in_ractor
    assert_ractor(<<-"end;")
      #{STR_DEFINITION_FOR_CHECK}
      r = Ractor.new do
        ENV.clear
        ENV["foo"] = "bar"
        ENV["baz"] = "qux"
        a = ENV.shift
        b = ENV.shift
        Ractor.yield [a,b]
        Ractor.yield ENV.shift
      end
      a,b = r.take
      check([a, b], [%w(foo bar), %w(baz qux)])
      assert_nil(r.take)
    end;
  end

  def test_invert_in_ractor
    assert_ractor(<<-"end;")
      #{STR_DEFINITION_FOR_CHECK}
      r = Ractor.new do
        ENV.clear
        ENV["foo"] = "bar"
        ENV["baz"] = "qux"
        Ractor.yield(ENV.invert)
      end
      check(r.take.to_a, [%w(bar foo), %w(qux baz)])
    end;
  end

  def test_replace_in_ractor
    assert_ractor(<<-"end;")
      #{STR_DEFINITION_FOR_CHECK}
      r = Ractor.new do
        ENV["foo"] = "xxx"
        ENV.replace({"foo"=>"bar", "baz"=>"qux"})
        Ractor.yield ENV.to_hash
        ENV.replace({"Foo"=>"Bar", "Baz"=>"Qux"})
        Ractor.yield ENV.to_hash
      end
      check(r.take.to_a, [%w(foo bar), %w(baz qux)])
      check(r.take.to_a, [%w(Foo Bar), %w(Baz Qux)])
    end;
  end

  def test_update_in_ractor
    assert_ractor(<<-"end;")
      #{STR_DEFINITION_FOR_CHECK}
      r = Ractor.new do
        ENV.clear
        ENV["foo"] = "bar"
        ENV["baz"] = "qux"
        ENV.update({"baz"=>"quux","a"=>"b"})
        Ractor.yield ENV.to_hash
        ENV.clear
        ENV["foo"] = "bar"
        ENV["baz"] = "qux"
        ENV.update({"baz"=>"quux","a"=>"b"}) {|k, v1, v2| k + "_" + v1 + "_" + v2 }
        Ractor.yield ENV.to_hash
      end
      check(r.take.to_a, [%w(foo bar), %w(baz quux), %w(a b)])
      check(r.take.to_a, [%w(foo bar), %w(baz baz_qux_quux), %w(a b)])
    end;
  end

  def test_huge_value_in_ractor
    assert_ractor(<<-"end;")
      huge_value = "bar" * 40960
      r = Ractor.new huge_value do |v|
        ENV["foo"] = "bar"
        #{str_for_yielding_exception_class("ENV['foo'] = v ")}
        Ractor.yield ENV["foo"]
      end

      if /mswin|ucrt/ =~ RUBY_PLATFORM
        #{str_for_assert_raise_on_yielded_exception_class(Errno::EINVAL, "r")}
        result = r.take
        assert_equal("bar", result)
      else
        exception_class = r.take
        assert_equal(NilClass, exception_class)
        result = r.take
        assert_equal(huge_value, result)
      end
    end;
  end

  def test_frozen_env_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        #{str_for_yielding_exception_class("ENV.freeze")}
      end
      #{str_for_assert_raise_on_yielded_exception_class(TypeError, "r")}
    end;
  end

  def test_frozen_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        ENV["#{PATH_ENV}"] = "/"
        ENV.each do |k, v|
          Ractor.yield [k.frozen?]
          Ractor.yield [v.frozen?]
        end
        ENV.each_key do |k|
          Ractor.yield [k.frozen?]
        end
        ENV.each_value do |v|
          Ractor.yield [v.frozen?]
        end
        ENV.each_key do |k|
          Ractor.yield [ENV[k].frozen?, "[\#{k.dump}]"]
          Ractor.yield [ENV.fetch(k).frozen?, "fetch(\#{k.dump})"]
        end
        Ractor.yield "finished"
      end
      while((params=r.take) != "finished")
        assert(*params)
      end
    end;
  end

  def test_shared_substring_in_ractor
    assert_ractor(<<-"end;")
      r = Ractor.new do
        bug12475 = '[ruby-dev:49655] [Bug #12475]'
        n = [*"0".."9"].join("")*3
        e0 = ENV[n0 = "E\#{n}"]
        e1 = ENV[n1 = "E\#{n}."]
        ENV[n0] = nil
        ENV[n1] = nil
        ENV[n1.chop] = "T\#{n}.".chop
        ENV[n0], e0 = e0, ENV[n0]
        ENV[n1], e1 = e1, ENV[n1]
        Ractor.yield [n, e0, e1, bug12475]
      end
      n, e0, e1, bug12475 = r.take
      assert_equal("T\#{n}", e0, bug12475)
      assert_nil(e1, bug12475)
    end;
  end

  def test_ivar_in_env_should_not_be_access_from_non_main_ractors
    assert_ractor <<~RUBY
    ENV.instance_eval{ @a = "hello" }
    assert_equal "hello", ENV.instance_variable_get(:@a)

    r_get =  Ractor.new do
      ENV.instance_variable_get(:@a)
    rescue Ractor::IsolationError => e
      e
    end
    assert_equal Ractor::IsolationError, r_get.take.class

    r_get =  Ractor.new do
      ENV.instance_eval{ @a }
    rescue Ractor::IsolationError => e
      e
    end

    assert_equal Ractor::IsolationError, r_get.take.class

    r_set = Ractor.new do
      ENV.instance_eval{ @b = "hello" }
    rescue Ractor::IsolationError => e
      e
    end

    assert_equal Ractor::IsolationError, r_set.take.class
    RUBY
  end

  if RUBY_PLATFORM =~ /bccwin|mswin|mingw/
    def test_memory_leak_aset
      bug9977 = '[ruby-dev:48323] [Bug #9977]'
      assert_no_memory_leak([], <<-'end;', "5_000.times(&doit)", bug9977, limit: 2.0)
        ENV.clear
        k = 'FOO'
        v = (ENV[k] = 'bar'*5000 rescue 'bar'*1500)
        doit = proc {ENV[k] = v}
        500.times(&doit)
      end;
    end

    def test_memory_leak_select
      bug9978 = '[ruby-dev:48325] [Bug #9978]'
      assert_no_memory_leak([], <<-'end;', "5_000.times(&doit)", bug9978, limit: 2.0)
        ENV.clear
        k = 'FOO'
        (ENV[k] = 'bar'*5000 rescue 'bar'*1500)
        doit = proc {ENV.select {break}}
        500.times(&doit)
      end;
    end

    def test_memory_crash_select
      assert_normal_exit(<<-'end;')
        1000.times {ENV["FOO#{i}"] = 'bar'}
        ENV.select {ENV.clear}
      end;
    end

    def test_memory_leak_shift
      bug9983 = '[ruby-dev:48332] [Bug #9983]'
      assert_no_memory_leak([], <<-'end;', "5_000.times(&doit)", bug9983, limit: 2.0)
        ENV.clear
        k = 'FOO'
        v = (ENV[k] = 'bar'*5000 rescue 'bar'*1500)
        doit = proc {ENV[k] = v; ENV.shift}
        500.times(&doit)
      end;
    end

    def test_utf8
      text = "testing \u{e5 e1 e2 e4 e3 101 3042}"
      ENV["test"] = text
      assert_equal text, ENV["test"]
    end

    def test_utf8_empty
      key = "VAR\u{e5 e1 e2 e4 e3 101 3042}"
      ENV[key] = "x"
      assert_equal "x", ENV[key]
      ENV[key] = ""
      assert_equal "", ENV[key]
      ENV[key] = nil
      assert_nil ENV[key]
    end
  end
end
