module RandomSpecs
  CustomRangeInteger = Struct.new(:value) do
    def to_int; value; end
    def <=>(other); to_int <=> other.to_int; end
    def -(other); self.class.new(to_int - other.to_int); end
    def +(other); self.class.new(to_int + other.to_int); end
  end

  CustomRangeFloat = Struct.new(:value) do
    def to_f; value; end
    def <=>(other); to_f <=> other.to_f; end
    def -(other); to_f - other.to_f; end
    def +(other); self.class.new(to_f + other.to_f); end
  end
end
