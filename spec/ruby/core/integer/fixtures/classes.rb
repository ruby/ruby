module IntegerSpecs
  class CoerceError < StandardError
  end

  class CoercibleNumeric
    def initialize(v) @v = v end
    def coerce(other) [self.class.new(other), self] end
    def >(other)  @v.to_i > other.to_i  end
    def >=(other) @v.to_i >= other.to_i end
    def <(other)  @v.to_i < other.to_i  end
    def <=(other) @v.to_i <= other.to_i end
    def to_i()    @v.to_i               end
  end
end
