assert_equal %q{ok}, %q{
  def m
    a = :ok
    $b = binding
  end
  m
  eval('a', $b)
}
assert_equal %q{[:ok, :ok2]}, %q{
  def m
    a = :ok
    $b = binding
  end
  m
  eval('b = :ok2', $b)
  eval('[a, b]', $b)
}
assert_equal %q{[nil, 1]}, %q{
  $ans = []
  def m
    $b = binding
  end
  m
  $ans << eval(%q{
    $ans << eval(%q{
      a
    }, $b)
    a = 1
  }, $b)
  $ans
}
assert_equal %q{C}, %q{
  Const = :top
  class C
    Const = :C
    def m
      binding
    end
  end
  eval('Const', C.new.m)
}
assert_equal %q{top}, %q{
  Const = :top
  a = 1
  class C
    Const = :C
    def m
      eval('Const', TOPLEVEL_BINDING)
    end
  end
  C.new.m
}
assert_equal %q{:ok
ok}, %q{
  class C
    $b = binding
  end
  eval %q{
    def m
      :ok
    end
  }, $b
  p C.new.m
}
assert_equal %q{ok}, %q{
  b = proc{
    a = :ok
    binding
  }.call
  a = :ng
  eval("a", b)
}
assert_equal %q{C}, %q{
  class C
    def foo
      binding
    end
  end
  C.new.foo.eval("self.class.to_s")
}
assert_equal %q{1}, %q{
  eval('1')
}
assert_equal %q{1}, %q{
  eval('a=1; a')
}
assert_equal %q{1}, %q{
  a = 1
  eval('a')
}
assert_equal %q{ok}, %q{
  __send__ :eval, %{
    :ok
  }
}
assert_equal %q{ok}, %q{
  1.__send__ :instance_eval, %{
    :ok
  }
}
assert_equal %q{1}, %q{
  1.instance_eval{
    self
  }
}
assert_equal %q{foo}, %q{
  'foo'.instance_eval{
    self
  }
}
assert_equal %q{1}, %q{
  class Fixnum
    Const = 1
  end
  1.instance_eval %{
    Const
  }
}
assert_equal %q{C}, %q{
  Const = :top
  class C
    Const = :C
  end
  C.module_eval{
    Const
  }
}
assert_equal %q{C}, %q{
  Const = :top
  class C
    Const = :C
  end
  C.class_eval %{
    def m
      Const
    end
  }
  C.new.m
}
assert_equal %q{C}, %q{
  Const = :top
  class C
    Const = :C
  end
  C.class_eval{
    def m
      Const
    end
  }
  C.new.m
}
assert_equal %q{[:top, :C, :top, :C]}, %q{
  Const = :top
  class C
    Const = :C
  end
  $nest = false
  $ans = []
  def m
    $ans << Const
    C.module_eval %{
      $ans << Const
      Boo = false unless defined? Boo
      unless $nest
        $nest = true
        m
      end
    }
  end
  m
  $ans
}
assert_equal %q{[10, main]}, %q{
  $nested = false
  $ans = []
  $pr = proc{
    $ans << self
    unless $nested
      $nested = true
      $pr.call
    end
  }
  class C
    def initialize &b
      10.instance_eval(&b)
    end
  end
  C.new(&$pr)
  $ans
}
