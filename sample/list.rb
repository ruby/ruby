# Linked list example
class MyElem
  # オブジェクト生成時に自動的に呼ばれるメソッド
  def initialize(item)
    # @変数はインスタンス変数(宣言は要らない)
    @data = item
    @succ = nil
  end

  def data
    @data
  end

  def succ
    @succ
  end

  # 「obj.data = val」としたときに暗黙に呼ばれるメソッド
  def succ=(new)
    @succ = new
  end
end

class MyList
  def add_to_list(obj)
    elt = MyElem.new(obj)
    if @head
      @tail.succ = elt
    else
      @head = elt
    end
    @tail = elt
  end

  def each
    elt = @head
    while elt
      yield elt
      elt = elt.succ
    end
  end

  # オブジェクトを文字列に変換するメソッド
  # これを再定義するとprintでの表現が変わる
  def to_s
    str = "<MyList:\n";
    for elt in self
      # 「str = str + elt.data.to_s + "\n"」の省略形
      str += elt.data.to_s + "\n"
    end
    str += ">"
    str
  end
end

class Point
  def initialize(x, y)
    @x = x; @y = y
    self
  end

  def to_s
    sprintf("%d@%d", @x, @y)
  end
end

# 大域変数は`$'で始まる．
$list1 = MyList.new
$list1.add_to_list(10)
$list1.add_to_list(20)
$list1.add_to_list(Point.new(2, 3))
$list1.add_to_list(Point.new(4, 5))
$list2 = MyList.new
$list2.add_to_list(20)
$list2.add_to_list(Point.new(4, 5))
$list2.add_to_list($list1)

# 曖昧でない限りメソッド呼び出しの括弧は省略できる
print "list1:\n", $list1, "\n"
print "list2:\n", $list2, "\n"
