# frozen_string_literal: true

require_relative "helper"

require "date"
require "rubygems/safe_marshal"

class TestGemSafeMarshal < Gem::TestCase
  def test_repeated_symbol
    assert_safe_load_as [:development, :development]
  end

  def test_repeated_string
    s = "hello"
    a = [s]
    assert_safe_load_as [s, a, s, a]
    assert_safe_load_as [s, s]
  end

  def test_recursive_string
    s = String.new("hello")
    s.instance_variable_set(:@type, s)
    with_const(Gem::SafeMarshal, :PERMITTED_IVARS, { "String" => %w[@type E] }) do
      assert_safe_load_as s, additional_methods: [:instance_variables]
    end
  end

  def test_recursive_array
    a = []
    a << a
    assert_safe_load_as a
  end

  def test_time_loads
    assert_safe_load_as Time.new
  end

  def test_string_with_encoding
    assert_safe_load_as String.new("abc", encoding: "US-ASCII")
    assert_safe_load_as String.new("abc", encoding: "UTF-8")
  end

  def test_string_with_ivar
    str = String.new("abc")
    str.instance_variable_set :@type, "type"
    with_const(Gem::SafeMarshal, :PERMITTED_IVARS, { "String" => %w[@type E] }) do
      assert_safe_load_as str
    end
  end

  def test_time_with_ivar
    with_const(Gem::SafeMarshal, :PERMITTED_IVARS, { "Time" => %w[@type offset zone nano_num nano_den submicro], "String" => "E" }) do
      assert_safe_load_as Time.new.tap {|t| t.instance_variable_set :@type, :runtime }
    end
  end

  secs = Time.new(2000, 12, 31, 23, 59, 59).to_i
  [
    Time.at(secs),
    Time.at(secs, in: "+04:00"),
    Time.at(secs, in: "-11:52"),
    Time.at(secs, in: "+00:00"),
    Time.at(secs, in: "-00:00"),
    Time.at(secs, 1, :millisecond),
    Time.at(secs, 1.1, :millisecond),
    Time.at(secs, 1.01, :millisecond),
    Time.at(secs, 1, :microsecond),
    Time.at(secs, 1.1, :microsecond),
    Time.at(secs, 1.01, :microsecond),
    Time.at(secs, 1, :nanosecond),
    Time.at(secs, 1.1, :nanosecond),
    Time.at(secs, 1.01, :nanosecond),
    Time.at(secs, 1.001, :nanosecond),
    Time.at(secs, 1.00001, :nanosecond),
    Time.at(secs, 1.00001, :nanosecond),
  ].each_with_index do |t, i|
    define_method("test_time_#{i} #{t.inspect}") do
      assert_safe_load_as t, additional_methods: [:ctime, :to_f, :to_r, :to_i, :zone, :subsec, :instance_variables, :dst?, :to_a]
    end
  end

  def test_floats
    [0.0, Float::INFINITY, Float::NAN, 1.1, 3e7].each do |f|
      assert_safe_load_as f
      assert_safe_load_as(-f)
    end
  end

  def test_hash_with_ivar
    h = { runtime: :development }
    h.instance_variable_set :@type, []
    with_const(Gem::SafeMarshal, :PERMITTED_IVARS, { "Hash" => %w[@type] }) do
      assert_safe_load_as(h)
    end
  end

  def test_hash_with_default_value
    assert_safe_load_as Hash.new([])
  end

  def test_hash_with_compare_by_identity
    pend "`read_user_class` not yet implemented"

    assert_safe_load_as Hash.new.compare_by_identity
  end

  def test_frozen_object
    assert_safe_load_as Gem::Version.new("1.abc").freeze
  end

  def test_date
    assert_safe_load_as Date.new(1994, 12, 9)
  end

  def test_rational
    assert_safe_load_as Rational(1, 3)
  end

  [
    0, 1, 2, 3, 4, 5, 6, 122, 123, 124, 127, 128, 255, 256, 257,
    2**16, 2**16 - 1, 2**20 - 1,
    2**28, 2**28 - 1,
    2**32, 2**32 - 1,
    2**63, 2**63 - 1
  ].
  each do |i|
    define_method("test_int_ #{i}") do
      assert_safe_load_as i
      assert_safe_load_as(-i)
      assert_safe_load_as(i + 1)
      assert_safe_load_as(i - 1)
    end
  end

  def test_gem_spec_disallowed_symbol
    e = assert_raise(Gem::SafeMarshal::Visitors::ToRuby::UnpermittedSymbolError) do
      spec = Gem::Specification.new do |s|
        s.name = "hi"
        s.version = "1.2.3"

        s.dependencies << Gem::Dependency.new("rspec", Gem::Requirement.new([">= 1.2.3"]), :runtime).tap {|d| d.instance_variable_set(:@name, :rspec) }
      end
      Gem::SafeMarshal.safe_load(Marshal.dump(spec))
    end

    assert_equal e.message, "Attempting to load unpermitted symbol \"rspec\" @ root.[9].[0].@name"
  end

  def assert_safe_load_as(x, additional_methods: [])
    dumped = Marshal.dump(x)
    loaded = Marshal.load(dumped)
    safe_loaded = Gem::SafeMarshal.safe_load(dumped)

    # NaN != NaN, for example
    if x == x # rubocop:disable Lint/BinaryOperatorWithIdenticalOperands
      assert_equal x, safe_loaded, "should load #{dumped.inspect}"
      assert_equal loaded, safe_loaded, "should equal what Marshal.load returns"
    end

    assert_equal x.to_s, safe_loaded.to_s, "should have equal to_s"
    assert_equal x.inspect, safe_loaded.inspect, "should have equal inspect"
    additional_methods.each do |m|
      assert_equal loaded.send(m), safe_loaded.send(m), "should have equal #{m}"
    end
    assert_equal Marshal.dump(loaded), Marshal.dump(safe_loaded), "should Marshal.dump the same"
  end

  def with_const(mod, name, new_value, &block)
    orig = mod.const_get(name)
    mod.send :remove_const, name
    mod.const_set name, new_value

    begin
      yield
    ensure
      mod.send :remove_const, name
      mod.const_set name, orig
      mod.send :private_constant, name
    end
  end
end
