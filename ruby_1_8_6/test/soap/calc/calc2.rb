class CalcService2
  def initialize(value = 0)
    @value = value
  end

  def set_value(value)
    @value = value
  end

  def get_value
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
