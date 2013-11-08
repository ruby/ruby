module Gem
  List = Struct.new(:value, :tail)

  class List
    def each
      n = self
      while n
        yield n.value
        n = n.tail
      end
    end

    def to_a
      ary = []
      n = self
      while n
        ary.unshift n.value
        n = n.tail
      end

      ary
    end

    def find
      n = self
      while n
        v = n.value
        return v if yield(v)
        n = n.tail
      end

      nil
    end

    def prepend(value)
      List.new value, self
    end

    def pretty_print q # :nodoc:
      q.pp to_a
    end

    def self.prepend(list, value)
      return List.new(value) unless list
      List.new value, list
    end
  end
end
