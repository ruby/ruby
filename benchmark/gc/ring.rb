# create many old objects

max = 30_000_000

class Ring
  attr_reader :next_ring
  def initialize n = nil
    @next_ring = n
  end


  def size
    s = 1
    ring = self
    while ring.next_ring
      s += 1
      ring = ring.next_ring
    end
    s
  end
end

ring = Ring.new

max.times{
  ring = Ring.new(ring)
}

# p ring.size
