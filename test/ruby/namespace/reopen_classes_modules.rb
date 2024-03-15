class NSDummyBuiltinA
  def call
    foo.upcase
  end
end

module NSDummyBuiltinB
  def call
    foo.upcase
  end
end

class NSUsualClassC
  def call
    foo.upcase
  end
end

module NSUsualModuleD
  def call
    foo.upcase
  end
end

module NSReopenClassesModules
  def self.test_a
    NSDummyBuiltinA.new.call
  end

  def self.test_b
    obj = Object.new
    obj.extend(NSDummyBuiltinB)
    obj.call
  end

  def self.test_c
    NSUsualClassC.new.call
  end

  def self.test_d
    obj = Object.new
    obj.extend(NSUsualModuleD)
    obj.call
  end
end
