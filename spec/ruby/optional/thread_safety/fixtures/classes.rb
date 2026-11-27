module ThreadSafetySpecs
  # Returns the number of processors, rounded up so it's always a multiple of 2
  def self.processors
    require 'etc'
    n = Etc.nprocessors
    raise "expected at least 1 processor" if n < 1
    n += 1 if n.odd? # ensure it's a multiple of 2
    n
  end

  class Counter
    def initialize
      @value = 0
      @mutex = Mutex.new
    end

    def get
      @mutex.synchronize { @value }
    end

    def increment
      @mutex.synchronize do
        @value += 1
      end
    end
  end

  class Barrier
    def initialize(parties)
      @parties = parties
      @counter = Counter.new
    end

    def wait
      @counter.increment
      Thread.pass until @counter.get == @parties
    end
  end
end
