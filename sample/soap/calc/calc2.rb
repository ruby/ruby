class CalcService2
  def initialize(value = 0)
    @value = value
  end

  def set(value)
    @value = value
  end

  def get
    @value
  end

  def +(rhs)
    @value + rhs
  end

  def -(rhs)
    @value - rhs
  end

  def *(rhs)
    @value * rhs
  end

  def /(rhs)
    @value / rhs
  end
end
