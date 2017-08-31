require 'mspec/guards/guard'

# Despite that these are inverses, the two classes are
# used to simplify MSpec guard reporting modes

class EndianGuard < SpecGuard
  def pattern
    @pattern ||= [1].pack('L')
  end
  private :pattern
end

class BigEndianGuard < EndianGuard
  def match?
    pattern[-1] == ?\001
  end
end

def big_endian(&block)
  BigEndianGuard.new.run_if(:big_endian, &block)
end

def little_endian(&block)
  BigEndianGuard.new.run_unless(:little_endian, &block)
end
