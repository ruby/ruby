module StringSpecs
  class ClassWithClassVariable
    @@a = "xxx"

    def foo
      "#@@a"
    end
  end
end
