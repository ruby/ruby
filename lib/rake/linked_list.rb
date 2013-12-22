module Rake

  # Polylithic linked list structure used to implement several data
  # structures in Rake.
  class LinkedList
    include Enumerable

    attr_reader :head, :tail

    def initialize(head, tail=EMPTY)
      @head = head
      @tail = tail
    end

    # Polymorphically add a new element to the head of a list. The
    # type of head node will be the same list type has the tail.
    def conj(item)
      self.class.cons(item, self)
    end

    # Is the list empty?
    def empty?
      false
    end

    # Lists are structurally equivalent.
    def ==(other)
      current = self
      while ! current.empty? && ! other.empty?
        return false if current.head != other.head
        current = current.tail
        other = other.tail
      end
      current.empty? && other.empty?
    end

    # Convert to string: LL(item, item...)
    def to_s
      items = map { |item| item.to_s }.join(", ")
      "LL(#{items})"
    end

    # Same as +to_s+, but with inspected items.
    def inspect
      items = map { |item| item.inspect }.join(", ")
      "LL(#{items})"
    end

    # For each item in the list.
    def each
      current = self
      while ! current.empty?
        yield(current.head)
        current = current.tail
      end
      self
    end

    # Make a list out of the given arguments. This method is
    # polymorphic
    def self.make(*args)
      result = empty
      args.reverse_each do |item|
        result = cons(item, result)
      end
      result
    end

    # Cons a new head onto the tail list.
    def self.cons(head, tail)
      new(head, tail)
    end

    # The standard empty list class for the given LinkedList class.
    def self.empty
      self::EMPTY
    end

    # Represent an empty list, using the Null Object Pattern.
    #
    # When inheriting from the LinkedList class, you should implement
    # a type specific Empty class as well. Make sure you set the class
    # instance variable @parent to the assocated list class (this
    # allows conj, cons and make to work polymorphically).
    class EmptyLinkedList < LinkedList
      @parent = LinkedList

      def initialize
      end

      def empty?
        true
      end

      def self.cons(head, tail)
        @parent.cons(head, tail)
      end
    end

    EMPTY = EmptyLinkedList.new
  end

end
