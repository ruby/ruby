module MainSpecs
  module Module
  end

  module WrapIncludeModule
  end

  DATA = {}
end


def main_public_method
end
public :main_public_method

def main_public_method2
end
public :main_public_method2

def main_private_method
end
private :main_private_method

def main_private_method2
end
private :main_private_method2
