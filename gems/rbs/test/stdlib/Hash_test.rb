require_relative "test_helper"

class HashTest < StdlibTest
  target Hash
  using hook.refinement

  # Hash[]
  def test_singleton_aref
    Hash[a: 42, b: 43]
    Hash[[[:a, 1], [:b, 3]]]
    Hash[:a, 1, :b, 3]
  end

  def test_singleton_try_convert
    Hash.try_convert({foo: 1})
    Hash.try_convert(nil)
    Hash.try_convert(42)
  end

  # test_<
  def test_less_than
    _ = { a: 1 } < { a: 1, b: 2 }
    _ = { a: 1 } < { 'a' => '1' }
  end

  # test_<=
  def test_less_than_equal
    _ = { a: 1 } <= { a: 1, b: 2 }
    _ = { a: 1 } <= { 'a' => '1' }
  end

  def test_eqeq
    _ = { a: 1 } == { a: 1 }
    _ = { a: 1 } == { b: 2 }
  end

  # test_>
  def test_greater_than
    _ = { a: 1 } > { a: 1, b: 2 }
    _ = { a: 1 } > { a: 1, b: '2' }
  end

  # test_>=
  def test_greater_than_equal
    _ = { a: 1 } >= { a: 1, b: 2 }
    _ = { a: 1 } >= { ab: 1, b: 2 }
  end

  def test_aref
    { foo: 1 }[:foo]
    { foo: 1 }[1]
  end

  def test_aset
    hash = { foo: 1 }
    hash[:a] = 2
    hash.store(:b, 3)
  end

  def test_any?
    { foo: 1, bar: 2 }.any?
    { foo: 1, bar: 2 }.any?(Array)
    # Pending because I tried to pass the test but I can't
    # { foo: 1, bar: 2 }.any? { |k, v| k == :foo && v == 1 }
  end

  def test_assoc
    { foo: 1, bar: 2 }.assoc(:foo)
    { foo: 1, bar: 2 }.assoc(:baz)
  end

  def test_clear
    { foo: 1, bar: 2 }.clear
  end

  def test_compact
    { a: nil }.compact
    { a: nil, b: 2 }.compact
    { b: 2 }.compact
  end

  def test_compact!
    { a: nil }.compact!
    { a: 1 }.compact!
  end

  def test_compare_by_identity
    { a: 1 }.compare_by_identity
  end

  def test_compare_by_identity?
    hash = { a: 1 }
    hash.compare_by_identity?
    hash.compare_by_identity
    hash.compare_by_identity?
  end

  def test_deconstruct_keys
    { a: 1 }.deconstruct_keys([])
    { a: 1 }.deconstruct_keys([:a])
    { a: 1 }.deconstruct_keys(nil)
  end

  # default and default=
  def test_default
    hash = {}
    hash.default
    hash.default = 1
    hash.default
  end

  # default_proc and default_proc=
  def test_default_proc
    hash = {}
    hash.default_proc
    hash.default_proc = proc { |h, k| k }
    hash.default_proc
    hash.default_proc = nil
    hash.default_proc
    hash.default_proc = :key
    hash.default_proc
  end

  def test_delete
    hash = { a: 123 }
    hash.delete(:a)
    hash.delete(:z)
    hash.delete(:z) { |k| "#{k} not found" }
  end

  def test_delete_if
    hash = { a: 123 }
    hash.delete_if
    hash.delete_if { |k, v| k == :a && v == 123 }
  end

  def test_dig
    hash = { a: 123, b: { foo: 1 } }
    hash.dig(:a)
    hash.dig(:b, :foo)
  end

  def test_each
    h = { a: 123 }

    h.each do |k, v|
      # nop
    end

    h.each do |x|
      # nop
    end

    h.each.each do |x, y|
      #
    end
  end

  def test_each_key
    h = { a: 123 }

    h.each_key do |k|
      # nop
    end

    h.each_key
  end

  def test_each_value
    h = { a: 123 }

    h.each_value do |v|
      # nop
    end

    h.each_value
  end

  def test_empty?
    {}.empty?
    { a: 1 }.empty?
  end

  def test_eql?
    { a: 1 }.eql?({ a: 1 })
    { a: 2 }.eql?({ a: 1 })
  end

  def test_fetch
    hash = { a: 1 }
    hash.fetch(:a)
    hash.fetch(:b, 2)
    hash.fetch(:b) { |key| key }
  end

  def test_fetch_values
    hash = { a: 1, b: 42 }
    hash.fetch_values(:a)
    hash.fetch_values(:a, :b)
    hash.fetch_values(:unknown) { |key| key }
  end

  def test_filter
    { a: 1, b: 2 }.filter
    { a: 1, b: 2 }.filter { |k, v| v == 1 }

    { a: 1, b: 2 }.select
    { a: 1, b: 2 }.select { |k, v| v == 1 }
  end

  def test_filter!
    { a: 1 }.filter!
    { a: 1 }.filter! { |k, v| v == 0 }
    { a: 1 }.filter! { |k, v| v == 1 }

    { a: 1 }.select!
    { a: 1 }.select! { |k, v| v == 0 }
    { a: 1 }.select! { |k, v| v == 1 }
  end

  def test_flatten
    h = { a: 1, b: 2, c: [3, 4, 5] }
    h.flatten
    h.flatten(1)
    h.flatten(2)
  end

  def test_has_key?
    h = { a: 1, b: 42 }
    h.has_key?(:a)
    h.has_key?(:x)
    h.include?(:b)
    h.key?(:c)
    h.member?(:x)
  end

  def test_has_value?
    h = { a: 1, b: 42 }
    h.has_value?(42)
    h.has_value?(2)
    h.value?(42)
    h.value?(2)
  end

  def test_hash
    { a: 1 }.hash
  end

  def test_index
    hash = { a: 1 }
    hash.index(1)
    hash.index(42)
    hash.key(3)
  end

  def test_inspect
    { a: 1 }.inspect
    { a: 1 }.to_s
  end

  def test_invert
    { a: 1, b: 42 }.invert
  end

  def test_keep_if
    hash = { a: 1, b: 2 }
    hash.keep_if
    hash.keep_if { |k, v| k == :a }
  end

  def test_keys
    { a: 1, b: 2 }.keys
  end

  def test_length
    { a: 1, b: 2 }.length
    { a: 1, b: 2 }.size
  end

  def test_merge
    hash = { a: 1, b: 2 }
    hash.merge({ 'k' => 'v' })
    hash.merge({ a: 3 }) { |k, v1, v2| [v1, v2] }
  end

  def test_merge!
    hash = { a: 1, b: 2 }
    hash.merge!({ 'k' => 'v' })
    hash.merge!({ a: 3 }) { |k, v1, v2| [v1, v2] }
    hash.update({ 'foo' => 42 })
  end

  def test_rassoc
    hash = { a: 1, b: 2 }
    hash.rassoc(2)
    hash.rassoc(42)
  end

  def test_rehash
    { a: 1, b: 2 }.rehash
  end

  def test_reject
    hash = { a: 1, b: 2 }
    hash.reject
    hash.reject { |k, v| k == :a }
  end

  def test_reject!
    hash = { a: 1, b: 2 }
    hash.reject!
    hash.reject! { |k, v| k == :a }
    hash.reject! { |k, v| k == :a }
  end

  def test_replace
    { a: 1 }.replace({ b: 2 })
  end

  def test_shift
    {}.shift
    { a: 42 }.shift
  end

  def test_slice
    { a: 42, b: 43, c: 44 }.slice(:a)
    { a: 42, b: 43, c: 44 }.slice(:a, :b)
  end

  def test_to_a
    { a: 42 }.to_a
  end

  def test_to_h
    { a: 42 }.to_h
    { a: 42 }.to_h { |k, v| [k.to_s, v.to_f] }
  end

  def test_to_proc
    { a: 1 }.to_proc.call(:a)
    { a: 1 }.to_proc.call(:b)
  end

  def test_transform_keys
    { a: 1, b: 2 }.transform_keys
    { a: 1, b: 2 }.transform_keys(&:to_s)
  end

  def test_transform_keys!
    { a: 1, b: 2 }.transform_keys!
    { a: 1, b: 2 }.transform_keys!(&:to_s)
  end

  def test_transform_values
    { a: 1, b: 2 }.transform_values
    { a: 1, b: 2 }.transform_values(&:to_s)
  end

  def test_transform_values!
    { a: 1, b: 2 }.transform_values!
    { a: 1, b: 2 }.transform_values!(&:to_s)
  end

  def test_values
    { a: 1, b: 2 }.values
  end

  def test_values_at
    { a: 1, b: 2, c: 3 }.values_at(:a, :b, :d)
  end

  def test_initialize
    Hash.new
    Hash.new(10)
    Hash.new { |hash, key| key.to_s }
  end
end
