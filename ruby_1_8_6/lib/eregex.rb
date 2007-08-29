# this is just a proof of concept toy.

class RegOr
  def initialize(re1, re2)
    @re1 = re1
    @re2 = re2
  end

  def =~ (str)
    @re1 =~ str or @re2 =~ str
  end
end

class RegAnd
  def initialize(re1, re2)
    @re1 = re1
    @re2 = re2
  end

  def =~ (str)
    @re1 =~ str and @re2 =~ str
  end
end

class Regexp
  def |(other)
    RegOr.new(self, other)
  end
  def &(other)
    RegAnd.new(self, other)
  end
end

if __FILE__ == $0
  p "abc" =~ /b/|/c/
  p "abc" =~ /b/&/c/
end
