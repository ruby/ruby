# Linked list example -- short version
# using _inspect

class Point
  def init_object(x, y)
    @x = x; @y = y
    self
  end

  def to_s
    sprintf("%d@%d", @x, @y)
  end
end
    
list1 = [10, 20, Point.new(2, 3), Point.new(4, 5)]
list2 = [20, Point.new(4, 5), list1]
print("list1: ", list1._inspect, "\n")
print("list2: ", list2._inspect, "\n")
