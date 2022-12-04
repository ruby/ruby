class TrueClass
  def hash
    raise "TrueClass#hash should not be called"
  end
end
class FalseClass
  def hash
    raise "FalseClass#hash should not be called"
  end
end
class Integer
  def hash
    raise "Integer#hash should not be called"
  end
end
class Float
  def hash
    raise "Float#hash should not be called"
  end
end
class String
  def hash
    raise "String#hash should not be called"
  end
end
class Symbol
  def hash
    raise "Symbol#hash should not be called"
  end
end
