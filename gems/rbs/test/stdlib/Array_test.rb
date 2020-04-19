require_relative "test_helper"
require "ruby/signature/test/test_helper"

class ArraySingletonTest < Minitest::Test
  include Ruby::Signature::Test::TypeAssertions

  testing "singleton(::Array)"

  def test_new
    assert_send_type "() -> ::Array[untyped]",
                     Array, :new
    assert_send_type "(Array[Integer]) -> ::Array[Integer]",
                     Array, :new, [1,2,3]
    assert_send_type "(Integer) -> Array[untyped]",
                     Array, :new, 3
    assert_send_type "(ToInt) -> Array[untyped]",
                     Array, :new, ToInt.new(3)
    assert_send_type "(ToInt, String) -> Array[String]",
                     Array, :new, ToInt.new(3), ""
    assert_send_type "(ToInt) { (Integer) -> :foo } -> Array[:foo]",
                     Array, :new, ToInt.new(3) do :foo end
  end

  def test_square_bracket
    assert_send_type "() -> Array[untyped]",
                     Array, :[]
    assert_send_type "(Integer, String) -> Array[Integer | String]",
                     Array, :[], 1, "2"
  end

  def test_try_connvert
    assert_send_type "(Integer) -> nil",
                     Array, :try_convert, 3
    assert_send_type "(ToArray) -> Array[Integer]",
                     Array, :try_convert, ToArray.new(1,2,3)
  end
end

class ArrayInstanceTest < Minitest::Test
  include Ruby::Signature::Test::TypeAssertions

  testing "::Array[::Integer]"

  def test_and
    assert_send_type "(Array[Integer]) -> Array[Integer]",
                     [1,2,3], :&, [2,3,4]
    assert_send_type "(ToArray) -> Array[Integer]",
                     [1,2,3], :&, ToArray.new(:a, :b, :c)
  end

  def test_mul
    assert_send_type "(Integer) -> Array[Integer]",
                     [1], :*, 3
    assert_send_type "(ToInt) -> Array[Integer]",
                     [1], :*, ToInt.new(3)
    assert_send_type "(String) -> String",
                     [1], :*, ","
    assert_send_type "(ToStr) -> String",
                     [1], :*, ToStr.new(",")
  end

  def test_plus
    assert_send_type "(Array[Integer]) -> Array[Integer]",
                     [1,2,3], :+, [4,5,6]
    assert_send_type "(Array[String]) -> Array[Integer | String]",
                     [1,2,3], :+, ["4", "5", "6"]
    assert_send_type "(ToArray) -> Array[Integer | String]",
                     [1,2,3], :+, ToArray.new("a")

    refute_send_type "(Enum) -> Array[Integer | String]",
                     [1,2,3], :+, Enum.new("a")
  end

  def test_minus
    assert_send_type "(Array[Integer]) -> Array[Integer]",
                     [1,2,3], :-, [4,5,6]
    assert_send_type "(ToArray) -> Array[Integer | String]",
                     [1,2,3], :-, ToArray.new("a")

    refute_send_type "(Enum) -> Array[Integer]",
                     [1,2,3], :-, Enum.new("a")
  end

  def test_lshift
    assert_send_type "(Integer) -> Array[Integer]",
                     [1,2,3], :<<, 4
  end

  def test_aref
    assert_send_type "(Integer) -> Integer",
                     [1,2,3], :[], 0
    assert_send_type "(Float) -> Integer",
                     [1,2,3], :[], 0.1
    assert_send_type "(ToInt) -> Integer",
                     [1], :[], ToInt.new(0)

    assert_send_type "(Integer, ToInt) -> Array[Integer]",
                     [1,2,3], :[], 0, ToInt.new(2)
    assert_send_type "(Integer, ToInt) -> nil",
                     [1,2,3], :[], 4, ToInt.new(2)

    assert_send_type "(Range[Integer]) -> Array[Integer]",
                     [1,2,3], :[], 0...1
    assert_send_type "(Range[Integer]) -> nil",
                     [1,2,3], :[], 5..8
  end

  def test_aupdate
    assert_send_type "(Integer, Integer) -> Integer",
                     [1,2,3], :[]=, 0, 0

    assert_send_type "(Integer, ToInt, Integer) -> Integer",
                     [1,2,3], :[]=, 0, ToInt.new(2), -1
    assert_send_type "(Integer, ToInt, Array[Integer]) -> Array[Integer]",
                     [1,2,3], :[]=, 0, ToInt.new(2), [-1]
    assert_send_type "(Integer, ToInt, nil) -> nil",
                     [1,2,3], :[]=, 0, ToInt.new(2), nil

    assert_send_type "(Range[Integer], Integer) -> Integer",
                     [1,2,3], :[]=, 0..2, -1
    assert_send_type "(Range[Integer], Array[Integer]) -> Array[Integer]",
                     [1,2,3], :[]=, 0...2, [-1]
    assert_send_type "(Range[Integer], nil) -> nil",
                     [1,2,3], :[]=, 0...2, nil
  end

  def test_all?
    assert_send_type "() -> bool",
                     [1,2,3], :all?
    assert_send_type "(singleton(Integer)) -> bool",
                     [1,2,3], :all?, Integer
    assert_send_type "() { (Integer) -> bool } -> bool",
                     [1,2,3], :all? do true end
  end

  def test_any?
    assert_send_type "() -> bool",
                     [1,2,3], :any?
    assert_send_type "(singleton(Integer)) -> bool",
                     [1,2,3], :any?, Integer
    assert_send_type "() { (Integer) -> bool } -> bool",
                     [1,2,3], :any? do true end
  end

  def test_assoc
    assert_send_type "(Integer) -> nil",
                     [1,2,3], :assoc, 0
  end

  def test_at
    assert_send_type "(Integer) -> Integer",
                     [1,2,3], :at, 0
    assert_send_type "(ToInt) -> Integer",
                     [1,2,3], :at, ToInt.new(0)
    assert_send_type "(ToInt) -> nil",
                     [1,2,3], :at, ToInt.new(-5)
  end

  def test_bsearch
    assert_send_type "() { (Integer) -> (true | false) } -> Integer",
                     [0,1,2,3,4], :bsearch do |x| x > 2 end
    assert_send_type "() { (Integer) -> (true | false) } -> nil",
                     [0,1,2,3,4], :bsearch do |x| x > 8 end

    assert_send_type "() { (Integer) -> Integer } -> Integer",
                     [0,1,2,3,4], :bsearch do |x| 3 <=> x end
    assert_send_type "() { (Integer) -> Integer } -> nil",
                     [0,1,2,3,4], :bsearch do |x| 8 <=> x end

  end

  def test_bsearch_index
    assert_send_type "() { (Integer) -> (true | false) } -> Integer",
                     [0,1,2,3,4], :bsearch_index do |x| x > 2 end
    assert_send_type "() { (Integer) -> (true | false) } -> nil",
                     [0,1,2,3,4], :bsearch_index do |x| x > 8 end

    assert_send_type "() { (Integer) -> Integer } -> Integer",
                     [0,1,2,3,4], :bsearch_index do |x| 3 <=> x end
    assert_send_type "() { (Integer) -> Integer } -> nil",
                     [0,1,2,3,4], :bsearch_index do |x| 8 <=> x end
  end

  def test_llear
    assert_send_type "() -> Array[Integer]",
                     [1,2,3], :clear
  end

  def test_collect
    assert_send_type "() { (Integer) -> String } -> Array[String]",
                     [1,2,3], :collect do |x| x.to_s end
  end

  def test_collect!
    assert_send_type "() { (Integer) -> Integer } -> Array[Integer]",
                     [1,2,3], :collect! do |x| x+1 end
  end

  def test_combination
    assert_send_type "(Integer) -> Enumerator[Array[Integer], Array[Integer]]",
                     [1,2,3], :combination, 3
    assert_send_type "(ToInt) -> Enumerator[Array[Integer], Array[Integer]]",
                     [1,2,3], :combination, ToInt.new(3)

    assert_send_type "(Integer) { (Array[Integer]) -> void } -> Array[Integer]",
                     [1,2,3], :combination, 3 do end
    assert_send_type "(ToInt) { (Array[Integer]) -> void } -> Array[Integer]",
                     [1,2,3], :combination, ToInt.new(3) do end
  end

  def test_compact
    assert_send_type "() -> Array[Integer]",
                     [1,2,3], :compact
    assert_send_type "() -> nil",
                     [1,2,3], :compact!
  end

  def test_concat
    assert_send_type "(Array[Integer], Array[Integer]) -> Array[Integer]",
                     [1,2,3], :concat, [4,5,6], [7,8,9]
  end

  def test_count
    assert_send_type "() -> Integer",
                     [1,2,3], :count
    assert_send_type "(Integer) -> Integer",
                     [1,2,3], :count, 1
    assert_send_type "() { (Integer) -> bool } -> Integer",
                     [1,2,3], :count do |x| x.odd? end
  end

  def test_cycle
    assert_send_type "() { (Integer) -> void } -> nil",
                     [1,2,3], :cycle do break end
    assert_send_type "(Integer) { (Integer) -> void } -> nil",
                     [1,2,3], :cycle, 3 do end
    assert_send_type "(ToInt) { (Integer) -> void } -> nil",
                     [1,2,3], :cycle, ToInt.new(2) do end
  end

  def test_deconstruct
    assert_send_type "() -> Array[Integer]",
                     [1,2,3], :deconstruct
  end

  def test_delete
    assert_send_type "(Integer) -> Integer",
                     [1,2,3], :delete, 2
    assert_send_type "(String) -> nil",
                     [1,2,3], :delete, ""

    assert_send_type "(Integer) { (Integer) -> String } -> Integer",
                     [1,2,3], :delete, 2 do "" end
    assert_send_type "(Symbol) { (Symbol) -> String } -> String",
                     [1,2,3], :delete, :foo do "" end
  end

  def test_delete_at
    assert_send_type "(Integer) -> Integer",
                     [1,2,3], :delete_at, 2
    assert_send_type "(Integer) -> nil",
                     [1,2,3], :delete_at, 100

    assert_send_type "(ToInt) -> nil",
                     [1,2,3], :delete_at, ToInt.new(300)
  end

  def test_delete_if
    assert_send_type "() { (Integer) -> bool } -> Array[Integer]",
                     [1,2,3], :delete_if do |x| x.odd? end
    assert_send_type "() -> Enumerator[Integer, Array[Integer]]",
                     [1,2,3], :delete_if
  end

  def test_difference
    assert_send_type "(Array[Integer]) -> Array[Integer]",
                     [1,2,3], :difference, [2]
  end

  def test_dig
    assert_send_type "(Integer) -> Integer",
                     [1,2,3], :dig, 1
    assert_send_type "(Integer) -> nil",
                     [1,2,3], :dig, 10
    assert_send_type "(ToInt) -> nil",
                     [1,2,3], :dig, ToInt.new(10)
  end

  def test_drop
    assert_send_type "(Integer) -> Array[Integer]",
                     [1,2,3], :drop, 2
    assert_send_type "(ToInt) -> Array[Integer]",
                     [1,2,3], :drop, ToInt.new(2)
  end

  def test_drop_while
    assert_send_type "() { (Integer) -> bool } -> Array[Integer]",
                     [1,2,3], :drop_while do false end
    assert_send_type "() -> Enumerator[Integer, Array[Integer]]",
                     [1,2,3], :drop_while
  end

  def test_each
    assert_send_type "() { (Integer) -> void } -> Array[Integer]",
                     [1,2,3], :each do end
    assert_send_type "() -> Enumerator[Integer, Array[Integer]]",
                     [1,2,3], :each
  end

  def test_each_index
    assert_send_type "() { (Integer) -> void } -> Array[Integer]",
                     [1,2,3], :each_index do end
    assert_send_type "() -> Enumerator[Integer, Array[Integer]]",
                     [1,2,3], :each_index
  end

  def test_empty?
    assert_send_type "() -> bool",
                     [1,2,3], :empty?
  end

  def test_fetch
    assert_send_type "(Integer) -> Integer",
                     [1,2,3], :fetch, 1
    assert_send_type "(ToInt) -> Integer",
                     [1,2,3], :fetch, ToInt.new(1)

    assert_send_type "(ToInt, String) -> Integer",
                     [1,2,3], :fetch, ToInt.new(1), "foo"
    assert_send_type "(ToInt, String) -> String",
                     [1,2,3], :fetch, ToInt.new(10), "foo"

    assert_send_type "(Integer) { (Integer) -> Symbol } -> Integer",
                     [1,2,3], :fetch, 1 do :hello end
    assert_send_type "(Integer) { (Integer) -> Symbol } -> Symbol",
                     [1,2,3], :fetch, 10 do :hello end
  end

  def test_fill
    assert_send_type "(Integer) -> Array[Integer]",
                     [1,2,3], :fill, 0

    assert_send_type "(Integer, nil) -> Array[Integer]",
                     [1,2,3], :fill, 0, nil
    assert_send_type "(Integer, ToInt) -> Array[Integer]",
                     [1,2,3], :fill, 0, ToInt.new(1)
    assert_send_type "(Integer, Integer) -> Array[Integer]",
                     [1,2,3], :fill, 0, 1
    assert_send_type "(Integer, Integer, Integer) -> Array[Integer]",
                     [1,2,3], :fill, 0, 1, 2
    assert_send_type "(Integer, ToInt, ToInt) -> Array[Integer]",
                     [1,2,3], :fill, 0, ToInt.new(1), ToInt.new(2)
    assert_send_type "(Integer, Integer, nil) -> Array[Integer]",
                     [1,2,3], :fill, 0, 1, nil

    assert_send_type "(Integer, Range[Integer]) -> Array[Integer]",
                     [1,2,3], :fill, 0, 1..2

    assert_send_type "() { (Integer) -> Integer } -> Array[Integer]",
                     [1,2,3], :fill do |i| i * 10 end
    assert_send_type "(ToInt, ToInt) { (Integer) -> Integer } -> Array[Integer]",
                     [1,2,3], :fill, ToInt.new(0), ToInt.new(2) do |i| i * 10 end
    assert_send_type "(Range[Integer]) { (Integer) -> Integer } -> Array[Integer]",
                     [1,2,3], :fill, 0..2 do |i| i * 10 end
  end

  def test_filter
    assert_send_type "() { (Integer) -> bool } -> Array[Integer]",
                     [1,2,3], :filter do |i| i < 1 end
    assert_send_type "() -> Enumerator[Integer, Array[Integer]]",
                     [1,2,3], :filter
  end

  def test_filter!
    assert_send_type "() { (Integer) -> bool } -> Array[Integer]",
                     [1,2,3], :filter! do |i| i < 0 end
    assert_send_type "() { (Integer) -> bool } -> nil",
                     [1,2,3], :filter! do |i| i > 0 end

    assert_send_type "() -> Enumerator[Integer, Array[Integer]?]",
                     [1,2,3], :filter!
  end

  def test_find_index
    assert_send_type "(Integer) -> Integer",
                     [1,2,3], :find_index, 1
    assert_send_type "(String) -> nil",
                     [1,2,3], :find_index, "0"

    assert_send_type "() { (Integer) -> bool } -> Integer",
                     [1,2,3], :find_index do |i| i.odd? end
    assert_send_type "() { (Integer) -> bool } -> nil",
                     [1,2,3], :find_index do |i| i < 0 end

    assert_send_type "() -> Enumerator[Integer, Integer?]",
                     [1,2,3], :find_index
  end

  def test_first
    assert_send_type "() -> Integer",
                     [1,2,3], :first
    assert_send_type "() -> nil",
                     [], :first

    assert_send_type "(Integer) -> Array[Integer]",
                     [1,2,3], :first, 2
    assert_send_type "(ToInt) -> Array[Integer]",
                     [1,2,3], :first, ToInt.new(2)
    assert_send_type "(Integer) -> Array[Integer]",
                     [1,2,3], :first, 0
  end

  def test_flatten
    assert_send_type "() -> Array[untyped]",
                     [1,2,3], :flatten
    assert_send_type "(Integer) -> Array[untyped]",
                     [1,2,3], :flatten, 3
    assert_send_type "(ToInt) -> Array[untyped]",
                     [1,2,3], :flatten, ToInt.new(3)
  end

  def test_flatten!
    assert_send_type "() -> Array[untyped]?",
                     [1,2,3], :flatten!
    assert_send_type "(Integer) -> Array[untyped]?",
                     [1,2,3], :flatten!, 3
    assert_send_type "(ToInt) -> Array[untyped]?",
                     [1,2,3], :flatten!, ToInt.new(3)
  end

  def test_include?
    assert_send_type "(Integer) -> bool",
                     [1,2,3], :include?, 1
    assert_send_type "(String) -> bool",
                     [1,2,3], :include?, ""
  end

  def test_index
    assert_send_type "(Integer) -> Integer",
                     [1,2,3], :index, 1
    assert_send_type "(String) -> nil",
                     [1,2,3], :index, "0"

    assert_send_type "() { (Integer) -> bool } -> Integer",
                     [1,2,3], :index do |i| i.odd? end
    assert_send_type "() { (Integer) -> bool } -> nil",
                     [1,2,3], :index do |i| i < 0 end

    assert_send_type "() -> Enumerator[Integer, Integer?]",
                     [1,2,3], :index
  end

  def test_insert
    assert_send_type "(Integer, Integer) -> Array[Integer]",
                     [1,2,3], :insert, 0, 10
    assert_send_type "(ToInt, Integer, Integer, Integer) -> Array[Integer]",
                     [1,2,3], :insert, ToInt.new(0), 10, 20, 30

    assert_send_type "(Integer) -> Array[Integer]",
                     [1,2,3], :insert, 0
  end

  def test_intersection
    assert_send_type "(Array[Integer]) -> Array[Integer]",
                     [1,2,3], :intersection, [2,3,4]
    assert_send_type "(Array[Integer], Array[String], ToArray) -> Array[Integer]",
                     [1,2,3], :intersection, [2,3,4], ["a"], ToArray.new(true, false)
    assert_send_type "() -> Array[Integer]",
                     [1,2,3], :intersection
  end

  def test_join
    assert_send_type "() -> String",
                     [1,2,3], :join

    assert_send_type "(String) -> String",
                     [1,2,3], :join, ","
    assert_send_type "(ToStr) -> String",
                     [1,2,3], :join, ToStr.new(",")
  end

  def test_keep_if
    assert_send_type "() { (Integer) -> false } -> Array[Integer]",
                     [1,2,3], :keep_if do false end
    assert_send_type "() { (Integer) -> true } -> Array[Integer]",
                     [1,2,3], :keep_if do true end

    assert_send_type "() -> Enumerator[Integer, Array[Integer]]",
                     [1,2,3], :keep_if
  end

  def test_last
    assert_send_type "() -> Integer",
                     [1,2,3], :last
    assert_send_type "() -> nil",
                     [], :last

    assert_send_type "(Integer) -> Array[Integer]",
                     [1,2,3], :last, 2
    assert_send_type "(ToInt) -> Array[Integer]",
                     [1,2,3], :last, ToInt.new(0)
  end

  def test_length
    assert_send_type "() -> Integer",
                     [1,2,3], :length
  end

  def test_map
    assert_send_type "() { (Integer) -> String } -> Array[String]",
                     [1,2,3], :map do |x| x.to_s end
    assert_send_type "() -> Enumerator[Integer, Array[untyped]]",
                     [1,2,3], :map
  end

  def test_map!
    assert_send_type "() { (Integer) -> Integer } -> Array[Integer]",
                     [1,2,3], :map! do |x| x+1 end
  end

  def test_max
    assert_send_type "() -> Integer",
                     [1,2,3], :max
    assert_send_type "() -> nil",
                     [], :max

    assert_send_type "(Integer) -> Array[Integer]",
                     [1,2,3], :max, 1
    assert_send_type "(ToInt) -> Array[Integer]",
                     [], :max, ToInt.new(1)

    assert_send_type "() { (Integer, Integer) -> Integer } -> Integer",
                     [1,2,3], :max do |_, _| 1 end
    assert_send_type "() { (Integer, Integer) -> Integer } -> nil",
                     [], :max do |_, _| 0 end

    assert_send_type "(ToInt) { (Integer, Integer) -> Integer } -> Array[Integer]",
                     [1,2,3], :max, ToInt.new(2) do |_, _| 0 end
    refute_send_type "(Integer) { (Integer, Integer) -> ToInt } -> Array[Integer]",
                     [1,2,3], :max, 2 do |_, _| ToInt.new(0) end
  end

  def test_minmax
    assert_send_type "() -> [Integer, Integer]",
                     [1,2,3], :minmax
    assert_send_type "() -> [Integer, Integer]",
                     [1], :minmax
    assert_send_type "() -> [nil, nil]",
                     [], :minmax

    assert_send_type "() { (Integer, Integer) -> Integer } -> [Integer, Integer]",
                     [1, 2], :minmax do |_, _| 0 end
  end

  def test_none?
    assert_send_type "() -> bool",
                     [1,2,3], :none?
    assert_send_type "(singleton(String)) -> bool",
                     [1,2,3], :none?, String
    assert_send_type "() { (Integer) -> bool } -> bool",
                     [1,2,3], :none? do |x| x.even? end
  end

  def test_one?
    assert_send_type "() -> bool",
                     [1,2,3], :one?
    assert_send_type "(singleton(String)) -> bool",
                     [1,2,3], :one?, String
    assert_send_type "() { (Integer) -> bool } -> bool",
                     [1,2,3], :one? do |x| x.even? end
  end

  def test_pack
    assert_send_type "(String) -> String",
                     [1,2,3], :pack, "ccc"
    assert_send_type "(ToStr) -> String",
                     [1,2,3], :pack, ToStr.new("ccc")

    assert_send_type "(String, buffer: String) -> String",
                     [1,2,3], :pack, "ccc", buffer: ""
    assert_send_type "(String, buffer: nil) -> String",
                     [1,2,3], :pack, "ccc", buffer: nil
    refute_send_type "(ToStr, buffer: ToStr) -> String",
                     [1,2,3], :pack, ToStr.new("ccc"), buffer: ToStr.new("")
  end

  def test_permutation
    assert_send_type "(Integer) -> Enumerator[Array[Integer], Array[Integer]]",
                     [1,2,3], :permutation, 2
    assert_send_type "() -> Enumerator[Array[Integer], Array[Integer]]",
                     [1,2,3], :permutation


    assert_send_type "(Integer) { (Array[Integer]) -> void } -> Array[Integer]",
                     [1,2,3], :permutation, 2 do end
    assert_send_type "() { (Array[Integer]) -> void } -> Array[Integer]",
                     [1,2,3], :permutation do end
  end

  def test_pop
    assert_send_type "() -> Integer",
                     [1,2,3], :pop
    assert_send_type "() -> nil",
                     [], :pop

    assert_send_type "(Integer) -> Array[Integer]",
                     [1,2,3], :pop, 1
    assert_send_type "(ToInt) -> Array[Integer]",
                     [1,2,3], :pop, ToInt.new(2)
  end

  def test_product
    assert_send_type "() -> Array[[Integer]]",
                     [1,2,3], :product
    assert_send_type "(Array[String]) -> Array[[Integer, String]]",
                     [1,2,3], :product, ["a", "b"]
    assert_send_type "(Array[String], Array[Symbol]) -> Array[[Integer, String, Symbol]]",
                     [1,2,3], :product, ["a", "b"], [:a, :b]
    assert_send_type "(Array[String], Array[Symbol], Array[true | false]) -> Array[Array[Integer | String | Symbol | true | false]]",
                     [1,2,3], :product, ["a", "b"], [:a, :b], [true, false]
  end

  def test_push
    assert_send_type "() -> Array[Integer]",
                     [1,2,3], :push
    assert_send_type "(Integer, Integer) -> Array[Integer]",
                     [1,2,3], :push, 4, 5
  end

  def test_rassoc
    assert_send_type "(String) -> nil",
                     [1,2,3], :rassoc, "3"
  end

  def test_reject
    assert_send_type "() { (Integer) -> bool } -> Array[Integer]",
                     [1,2,3], :reject do |x| x.odd? end
    assert_send_type "() -> Enumerator[Integer, Array[Integer]]",
                     [1,2,3], :reject
  end

  def test_reject!
    assert_send_type "() { (Integer) -> bool } -> Array[Integer]",
                     [1,2,3], :reject! do |x| x.odd? end
    assert_send_type "() { (Integer) -> bool } -> nil",
                     [1,2,3], :reject! do |x| x == "" end

    assert_send_type "() -> Enumerator[Integer, Array[Integer]?]",
                     [1,2,3], :reject!
  end

  def test_repeated_combination
    assert_send_type "(ToInt) { (Array[Integer]) -> nil } -> Array[Integer]",
                     [1,2,3], :repeated_combination, ToInt.new(2) do end
    assert_send_type "(ToInt) -> Enumerator[Array[Integer], Array[Integer]]",
                     [1,2,3], :repeated_combination, ToInt.new(2)
  end

  def test_repeated_permutation
    assert_send_type "(ToInt) { (Array[Integer]) -> nil } -> Array[Integer]",
                     [1,2,3], :repeated_permutation, ToInt.new(2) do end
    assert_send_type "(ToInt) -> Enumerator[Array[Integer], Array[Integer]]",
                     [1,2,3], :repeated_permutation, ToInt.new(2)
  end

  def test_replace
    assert_send_type "(Array[Integer]) -> Array[Integer]",
                     [1,2,3], :replace, [2,3,4]
  end

  def test_reverse
    assert_send_type "() -> Array[Integer]",
                     [1,2,3], :reverse
  end

  def test_reverse!
    assert_send_type "() -> Array[Integer]",
                     [1,2,3], :reverse!
  end

  def test_reverse_each
    assert_send_type "() { (Integer) -> nil } -> Array[Integer]",
                     [1,2,3], :reverse_each do end
    assert_send_type "() -> Enumerator[Integer, Array[Integer]]",
                     [2,3,4], :reverse_each
  end

  def test_rindex
    assert_send_type "(Integer) -> Integer",
                     [1,2,3], :rindex, 1
    assert_send_type "(String) -> nil",
                     [1,2,3], :rindex, "0"

    assert_send_type "() { (Integer) -> bool } -> Integer",
                     [1,2,3], :rindex do |i| i.odd? end
    assert_send_type "() { (Integer) -> bool } -> nil",
                     [1,2,3], :rindex do |i| i < 0 end

    assert_send_type "() -> Enumerator[Integer, Integer?]",
                     [1,2,3], :rindex
  end

  def test_rotate
    assert_send_type "() -> Array[Integer]",
                     [1,2,3], :rotate
    assert_send_type "(Integer) -> Array[Integer]",
                     [1,2,3], :rotate, 3
    assert_send_type "(ToInt) -> Array[Integer]",
                     [1,2,3], :rotate, ToInt.new(2)
  end

  def test_rotate!
    assert_send_type "() -> Array[Integer]",
                     [1,2,3], :rotate!
    assert_send_type "(Integer) -> Array[Integer]",
                     [1,2,3], :rotate!, 3
    assert_send_type "(ToInt) -> Array[Integer]",
                     [1,2,3], :rotate!, ToInt.new(2)
  end

  def test_sample
    assert_send_type "() -> Integer",
                     [1,2,3], :sample
    assert_send_type "() -> nil",
                     [], :sample
    assert_send_type "(random: Random) -> Integer",
                     [1,2,3], :sample, random: Random.new(1)

    assert_send_type "(Integer) -> Array[Integer]",
                     [1,2,3], :sample, 2
    assert_send_type "(ToInt, random: Random) -> Array[Integer]",
                     [1,2,3], :sample, ToInt.new(2), random: Random.new(2)
  end

  def test_select
    assert_send_type "() { (Integer) -> bool } -> Array[Integer]",
                     [1,2,3], :select do |i| i < 1 end
    assert_send_type "() -> Enumerator[Integer, Array[Integer]]",
                     [1,2,3], :select
  end

  def test_select!
    assert_send_type "() { (Integer) -> bool } -> Array[Integer]",
                     [1,2,3], :select! do |i| i < 1 end
    assert_send_type "() { (Integer) -> bool } -> nil",
                     [1,2,3], :select! do true end
    assert_send_type "() -> Enumerator[Integer, Array[Integer]?]",
                     [1,2,3], :select!
  end

  def test_shift
    assert_send_type "() -> Integer",
                     [1,2,3], :shift
    assert_send_type "(ToInt) -> Array[Integer]",
                     [1,2,3], :shift, ToInt.new(1)
  end

  def test_shuffle
    assert_send_type "() -> Array[Integer]",
                     [1,2,3], :shuffle
    assert_send_type "(random: Random) -> Array[Integer]",
                     [1,2,3], :shuffle, random: Random.new(2)
  end

  def test_shuffle!
    assert_send_type "() -> Array[Integer]",
                     [1,2,3], :shuffle!
    assert_send_type "(random: Random) -> Array[Integer]",
                     [1,2,3], :shuffle!, random: Random.new(2)
  end

  def test_slice
    assert_send_type "(Integer) -> Integer",
                     [1,2,3], :slice, 1
    assert_send_type "(ToInt) -> nil",
                     [1,2,3], :slice, ToInt.new(11)

    assert_send_type "(Integer, Integer) -> Array[Integer]",
                     [1,2,3], :slice, 1, 2
    assert_send_type "(ToInt, ToInt) -> nil",
                     [1,2,3], :slice, ToInt.new(10), ToInt.new(2)

    assert_send_type "(Range[Integer]) -> Array[Integer]",
                     [1,2,3], :slice, 1...2
    assert_send_type "(Range[Integer]) -> nil",
                     [1,2,3], :slice, 11...21
  end

  def test_slice!
    assert_send_type "(Integer) -> Integer",
                     [1,2,3], :slice!, 1
    assert_send_type "(ToInt) -> nil",
                     [1,2,3], :slice!, ToInt.new(11)

    assert_send_type "(Integer, Integer) -> Array[Integer]",
                     [1,2,3], :slice!, 1, 2
    assert_send_type "(ToInt, ToInt) -> nil",
                     [1,2,3], :slice!, ToInt.new(10), ToInt.new(2)

    assert_send_type "(Range[Integer]) -> Array[Integer]",
                     [1,2,3], :slice!, 1...2
    assert_send_type "(Range[Integer]) -> nil",
                     [1,2,3], :slice!, 11...21
  end

  def test_sort
    assert_send_type "() -> Array[Integer]",
                     [1,2,3], :sort

    assert_send_type "() { (Integer, Integer) -> Integer } -> Array[Integer]",
                     [1,2,3], :sort do |a, b| b <=> a end

    # returning nil from block type checks but causes an error
    refute_send_type "() { (Integer, Integer) -> nil } -> Array[Integer]",
                     [1,2,3], :sort do end
  end

  def test_sort!
    assert_send_type "() -> Array[Integer]",
                     [1,2,3], :sort!

    assert_send_type "() { (Integer, Integer) -> Integer } -> Array[Integer]",
                     [1,2,3], :sort! do |a, b| b <=> a end

    # returning nil from block type checks but causes an error
    refute_send_type "() { (Integer, Integer) -> nil } -> Array[Integer]",
                     [1,2,3], :sort! do end
  end

  def test_sort_by!
    assert_send_type "() { (Integer) -> String } -> Array[Integer]",
                     [1,2,3], :sort_by! do |x| x.to_s end
    assert_send_type "() -> Enumerator[Integer, Array[Integer]]",
                     [1,2,3], :sort_by!
  end

  def test_sum
    assert_send_type "() -> Integer",
                     [1,2,3], :sum
    assert_send_type "(Integer) -> Integer",
                     [1,2,3], :sum, 2

    assert_send_type "(String) { (Integer) -> String } -> String",
                     [1,2,3], :sum, "**" do |x| x.to_s end
  end

  def test_take
    assert_send_type "(Integer) -> Array[Integer]",
                     [1,2,3], :take, 2
    assert_send_type "(ToInt) -> Array[Integer]",
                     [1,2,3], :take, ToInt.new(2)
  end

  def test_take_while
    assert_send_type "() { (Integer) -> bool } -> Array[Integer]",
                     [1,2,3], :take_while do |x| x < 2 end
    assert_send_type "() -> Enumerator[Integer, Array[Integer]]",
                     [1,2,3], :take_while
  end

  def test_to_a
    assert_send_type "() -> Array[Integer]",
                     [1,2,3], :to_a
  end

  def test_to_ary
    assert_send_type "() -> Array[Integer]",
                     [1,2,3], :to_ary
  end

  def test_to_h
    testing "::Array[[::String, ::Integer]]" do
      assert_send_type "() -> Hash[String, Integer]",
                       [["foo", 1], ["bar", 2]], :to_h
    end

    assert_send_type "() { (Integer) -> [Symbol, String] } -> Hash[Symbol, String]",
                     [1,2,3], :to_h do |i| [:"s#{i}", i.to_s ] end
  end

  def test_transpose
    testing "::Array[[::String, ::Integer]]" do
      assert_send_type "() -> [Array[String], Array[Integer]]",
                       [["foo", 1], ["bar", 2]], :transpose
    end
  end

  def test_union
    assert_send_type "() -> Array[Integer]",
                     [1,2,3], :union
    assert_send_type "(Array[Symbol]) -> Array[Integer | Symbol]",
                     [1,2,3], :union, [:x, :y, :z]
  end

  def test_uniq
    assert_send_type "() -> Array[Integer]",
                     [1,2,3], :uniq
    assert_send_type "() { (Integer) -> String } -> Array[Integer]",
                     [1,2,3], :uniq do |i| i.to_s end
  end

  def test_uniq!
    assert_send_type "() -> Array[Integer]",
                     [1,2,3,1], :uniq!
    assert_send_type "() -> nil",
                     [1,2,3], :uniq!
    assert_send_type "() { (Integer) -> String } -> Array[Integer]",
                     [1,2,3, 1], :uniq! do |i| i.to_s end
    assert_send_type "() { (Integer) -> String } -> nil",
                     [1,2,3], :uniq! do |i| i.to_s end
  end

  def test_unshift
    assert_send_type "() -> Array[Integer]",
                     [1,2,3], :unshift
    assert_send_type "(Integer, Integer) -> Array[Integer]",
                     [1,2,3], :unshift, 4, 5
  end

  def test_values_at
    assert_send_type "() -> Array[Integer]",
                     [1,2,3], :values_at
    assert_send_type "(Integer) -> Array[Integer]",
                     [1,2,3], :values_at, 2
    assert_send_type "(ToInt, Integer) -> Array[Integer?]",
                     [1,2,3], :values_at, ToInt.new(2), 3
    assert_send_type "(ToInt, Range[Integer]) -> Array[Integer?]",
                     [1,2,3], :values_at, ToInt.new(2), 0..1
  end

  def test_zip
    assert_send_type "(Array[String]) -> Array[[Integer, String?]]",
                     [1,2,3], :zip, ["a", "b"]
    assert_send_type "(Array[String]) -> Array[[Integer, String]]",
                     [1,2,3], :zip, ["a", "b", "c", "d"]
    assert_send_type "(Array[String], Array[Symbol]) -> Array[Array[untyped]]",
                     [1,2,3], :zip, ["a", "b"], [:foo, :bar]

    assert_send_type "(Array[String]) { ([Integer, String?]) -> true } -> nil",
                     [1,2,3], :zip, ["a", "b"] do true end
  end

  def test_vbar
    assert_send_type "(Array[String]) -> Array[Integer | String]",
                     [1,2,3], :|, ["x", "y"]
  end
end
