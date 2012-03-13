require 'test/unit'

class TestLazyEnumerator < Test::Unit::TestCase
  class Step
    include Enumerable
    attr_reader :current, :args

    def initialize(enum)
      @enum = enum
      @current = nil
      @args = nil
    end

    def each(*args)
      @args = args
      @enum.each {|i| @current = i; yield i}
    end
  end

  def test_initialize
    assert_equal([1, 2, 3], [1, 2, 3].lazy.to_a)
    assert_equal([1, 2, 3], Enumerable::Lazy.new([1, 2, 3]).to_a)
    assert_equal([1, 2, 3], Step.new(1..3).lazy.to_a)
  end

  def test_each_args
    a = Step.new(1..3)
    assert_equal(1, a.lazy.each(4).first)
    assert_equal([4], a.args)
  end

  def test_each_line
    name = lineno = nil
    File.open(__FILE__) do |f|
      f.each("").map do |paragraph|
        paragraph[/\A\s*(.*)/, 1]
      end.find do |line|
        if name = line[/^class\s+(\S+)/, 1]
          lineno = f.lineno
          true
        end
      end
    end
    assert_equal(self.class.name, name)
    assert_operator(lineno, :>, 2)

    name = lineno = nil
    File.open(__FILE__) do |f|
      f.lazy.each("").map do |paragraph|
        paragraph[/\A\s*(.*)/, 1]
      end.find do |line|
        if name = line[/^class\s+(\S+)/, 1]
          lineno = f.lineno
          true
        end
      end
    end
    assert_equal(self.class.name, name)
    assert_equal(2, lineno)
  end

  def test_select
    a = Step.new(1..6)
    assert_equal(4, a.select {|x| x > 3}.first)
    assert_equal(6, a.current)
    assert_equal(4, a.lazy.select {|x| x > 3}.first)
    assert_equal(4, a.current)

    a = Step.new(['word', nil, 1])
    assert_raise(TypeError) {a.select {|x| "x"+x}.first}
    assert_equal(nil, a.current)
    assert_equal("word", a.lazy.select {|x| "x"+x}.first)
    assert_equal("word", a.current)
  end

  def test_map
    a = Step.new(1..3)
    assert_equal(2, a.map {|x| x * 2}.first)
    assert_equal(3, a.current)
    assert_equal(2, a.lazy.map {|x| x * 2}.first)
    assert_equal(1, a.current)
  end

  def test_flat_map
    a = Step.new(1..3)
    assert_equal(2, a.flat_map {|x| [x * 2]}.first)
    assert_equal(3, a.current)
    assert_equal(2, a.lazy.flat_map {|x| [x * 2]}.first)
    assert_equal(1, a.current)
  end

  def test_reject
    a = Step.new(1..6)
    assert_equal(4, a.reject {|x| x < 4}.first)
    assert_equal(6, a.current)
    assert_equal(4, a.lazy.reject {|x| x < 4}.first)
    assert_equal(4, a.current)

    a = Step.new(['word', nil, 1])
    assert_equal(nil, a.reject {|x| x}.first)
    assert_equal(1, a.current)
    assert_equal(nil, a.lazy.reject {|x| x}.first)
    assert_equal(nil, a.current)
  end

  def test_grep
    a = Step.new('a'..'f')
    assert_equal('c', a.grep(/c/).first)
    assert_equal('f', a.current)
    assert_equal('c', a.lazy.grep(/c/).first)
    assert_equal('c', a.current)
  end
end
