class CApiKernelSpecs
  class ClassWithPublicMethod
    def public_method(*, **)
      :public
    end
  end

  class ClassWithPrivateMethod
    private def private_method(*, **)
      :private
    end
  end

  class ClassWithProtectedMethod
    protected def protected_method(*, **)
      :protected
    end
  end
end
