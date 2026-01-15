
module SetSpecs
  # This class is used to test the interaction of "Set-like" objects with real Sets
  #
  # These "Set-like" objects reply to is_a?(Set) with true and thus real Set objects are able to transparently
  # interoperate with them in a duck-typing manner.
  class SetLike
    include Enumerable

    def is_a?(klass)
      super || klass == ::Set
    end

    def initialize(entries)
      @entries = entries
    end

    def each(&block)
      @entries.each(&block)
    end

    def inspect
      "#<#{self.class}: {#{map(&:inspect).join(", ")}}>"
    end

    def size
      @entries.size
    end
  end
end
