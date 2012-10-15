class C
  attr_accessor :a, :b
  def initialize
    @a = nil
    @b = nil
  end
end
obj = C.new
i = 0
while i<30_000_000 # while loop 1
  i += 1
  obj.a = 1
  obj.b = 2
end
