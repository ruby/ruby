# Linked list program
class MyElem
  def MyElem.new(item)
    super.init(item)
  end
  
  def init(item)
    @data = item
    @next = nil
    self
  end

  def data
    @data
  end

  def next
    @next
  end

  def next=(new)
    @next = new
  end
end

class MyList
  def add_to_list(obj)
    elt = MyElem.new(obj)
    if @head
      @tail.next = elt
    else
      @head = elt
    end
    @tail = elt
  end

  def each
    elt = @head
    while elt
      yield elt
      elt = elt.next
    end
  end

  def to_s
    str = "<MyList:\n";
    for elt in self
      str += elt.data.to_s + "\n"
    end
    str += ">"
    str
  end
end

class Point
  def Point.new(x, y)
    super.init(x, y)
  end

  def init(x, y)
    @x = x; @y = y
    self
  end

  def to_s
    sprintf("%d@%d", @x, @y)
  end
end
    
list1 = MyList.new
list1.add_to_list(10)
list1.add_to_list(20)
list1.add_to_list(Point.new(2, 3))
list1.add_to_list(Point.new(4, 5))
list2 = MyList.new
list2.add_to_list(20)
list2.add_to_list(Point.new(4, 5))
list2.add_to_list(list1)

print("list1:\n", list1, "\n")
print("list2:\n", list2, "\n")
