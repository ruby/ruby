class NSBuiltinSMethodsC
  p(receiver: self, klass: self.class)
  def self.yay
    prefix + "yay-c"
  end
  def yay
    "yaaaaaaaaay"
  end
end

class NSBuiltinSMethodsC
  class << self
    def foo
      prefix + "foo-c"
    end
  end
end

module NSBuiltinSMethodsM
  def self.yay
    prefix + "yay-m"
  end
end

module NSBuiltinSMethodsM
  class << self
    def foo
      prefix + "foo-m"
    end
  end
end

module SingletonMethods
  def self.class_def_with_self
    p NSBuiltinSMethodsC.create.yay
    p(receiver: NSBuiltinSMethodsC, klass: NSBuiltinSMethodsC.class)
    NSBuiltinSMethodsC.yay
  end

  def self.class_open_self
    NSBuiltinSMethodsC.foo
  end

  def self.module_def_with_self
    NSBuiltinSMethodsM.yay
  end

  def self.module_open_self
    NSBuiltinSMethodsM.foo
  end
end
