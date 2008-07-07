module REXML
  class SyncEnumerator
    include Enumerable

    # Creates a new SyncEnumerator which enumerates rows of given
    # Enumerable objects.
    def initialize(*enums)
      @gens = enums
      @biggest = @gens[0]
      @gens.each {|x| @biggest = x if x.size > @biggest.size }
    end

    # Returns the number of enumerated Enumerable objects, i.e. the size
    # of each row.
    def size
      @gens.size
    end

    # Returns the number of enumerated Enumerable objects, i.e. the size
    # of each row.
    def length
      @gens.length
    end

    # Enumerates rows of the Enumerable objects.
    def each
      @biggest.zip( *@gens ) {|a|
        yield(*a[1..-1])
      }
      self
    end
  end
end
