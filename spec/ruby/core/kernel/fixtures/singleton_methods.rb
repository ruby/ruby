module SingletonMethodsSpecs
  module Prepended
    def mspec_test_kernel_singleton_methods
    end
    public :mspec_test_kernel_singleton_methods
  end

  ::Module.prepend Prepended

  module SelfExtending
    extend self
  end
end
