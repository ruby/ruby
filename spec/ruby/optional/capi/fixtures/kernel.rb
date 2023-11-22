class CApiKernelSpecs
  class ClassWithPublicMethod
    def public_method(*, **)
      0
    end
  end

  class ClassWithPrivateMethod
    private def private_method(*, **)
      0
    end
  end

  class ClassWithProtectedMethod
    protected def protected_method(*, **)
      0
    end
  end
end
