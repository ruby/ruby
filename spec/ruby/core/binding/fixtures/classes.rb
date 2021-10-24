module BindingSpecs
  class Demo
    def initialize(n)
      @secret = n
    end

    def square(n)
      n * n
    end

    def get_binding_and_line
      a = true
      [binding, __LINE__]
    end

    def get_binding
      get_binding_and_line[0]
    end

    def get_line_of_binding
      get_binding_and_line[1]
    end

    def get_file_of_binding
      __FILE__
    end

    def get_binding_with_send_and_line
      [send(:binding), __LINE__]
    end

    def get_binding_and_method
      [binding, :get_binding_and_method]
    end

    def get_binding_with_send_and_method
      [send(:binding), :get_binding_with_send_and_method]
    end

    def get_empty_binding
      binding
    end

    def get_binding_in_block
      a = true
      1.times do
        b = false
        return binding
      end
    end
  end

  module AddFooToString
    refine(String) do
      def foo
        "foo"
      end
    end
  end
  class Refined
    using AddFooToString
    def self.refined_binding
      binding
    end
  end
end
