
i=0
while i<20000000
  x = 1 # "foo"
  i+=1
end

__END__

class Range
  def each
    f = self.first
    l = self.last
    while f < l
      yield
      f = f.succ
    end
  end
end

(0..10000000).each{
}

__END__
class Fixnum_
  def times
    i = 0
    while i<self
      yield(i)
      i+=1
    end
  end
end

10000000.times{
}
__END__

ths = (1..10).map{
  Thread.new{
    1000000.times{
    }
  }
}
ths.each{|e|
  e.join
}

__END__
$pr = proc{}
def m
  $pr.call
end

1000000.times{|e|
  m
}
