module VariablesSpecs
  class ParAsgn
    attr_accessor :x

    def initialize
      @x = 0
    end

    def inc
      @x += 1
    end

    def to_ary
      [1,2,3,4]
    end
  end

  class OpAsgn
    attr_accessor :a, :b, :side_effect

    def do_side_effect
      self.side_effect = true
      return @a
    end

    def do_more_side_effects
      @a += 5
      self
    end

    def do_bool_side_effects
      @b += 1
      self
    end
  end

  class Hashalike
    def [](k) k end
    def []=(k, v) [k, v] end
  end

  def self.reverse_foo(a, b)
    return b, a
  end

  class ArrayLike
    def initialize(array)
      @array = array
    end

    def to_a
      @array
    end
  end

  class ArraySubclass < Array
  end

  class PrivateMethods
    private

    def to_ary
      [1, 2]
    end

    def to_a
      [3, 4]
    end
  end

  class ToAryNil
    def to_ary
    end
  end

  class Chain
    def self.without_parenthesis a
      a
    end
  end

  def self.false
    false
  end

  class EvalOrder
    attr_reader :order

    def initialize
      @order = []
    end

    def reset
      @order = []
    end

    def foo
      self << "foo"
      FooClass.new(self)
    end

    def bar
      self << "bar"
      BarClass.new(self)
    end

    def a
      self << "a"
    end

    def b
      self << "b"
    end

    def node
      self << "node"

      node = Node.new
      node.left = Node.new
      node.left.right = Node.new

      node
    end

    def <<(value)
      order << value
    end

    class FooClass
      attr_reader :evaluator

      def initialize(evaluator)
        @evaluator = evaluator
      end

      def []=(_index, _value)
        evaluator << "foo[]="
      end
    end

    class BarClass
      attr_reader :evaluator

      def initialize(evaluator)
        @evaluator = evaluator
      end

      def baz=(_value)
        evaluator << "bar.baz="
      end
    end

    class Node
      attr_accessor :left, :right
    end
  end
end
