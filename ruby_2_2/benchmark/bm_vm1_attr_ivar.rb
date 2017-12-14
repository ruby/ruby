class C
  attr_reader :a, :b
  def initialize
    @a = nil
    @b = nil
  end
end
obj = C.new
i = 0
while i<30_000_000 # while loop 1
  i += 1
  j = obj.a
  k = obj.b
end
