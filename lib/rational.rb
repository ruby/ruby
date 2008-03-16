class Fixnum

  alias quof fdiv

  alias power! **
  alias rpower **

end

class Bignum

  alias quof fdiv

  alias power! **
  alias rpower **

end

class Integer

  def gcd(other)
    min = self.abs
    max = other.abs
    while min > 0
      tmp = min
      min = max % min
      max = tmp
    end
    max
  end

  def lcm(other)
    if self.zero? or other.zero?
      0
    else
      (self.div(self.gcd(other)) * other).abs
    end
  end

  def gcdlcm(other)
    gcd = self.gcd(other)
    if self.zero? or other.zero?
      [gcd, 0]
    else
      [gcd, (self.div(gcd) * other).abs]
    end
  end

end
