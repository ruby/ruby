module KernelSpecs
  module RaiseSpecs
    class UniqueClass
      def self.with_raise
        yield
      end
    end
  end
end
