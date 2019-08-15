module EnsureSpec
  class Container
    attr_reader :executed

    def initialize
      @executed = []
    end

    def raise_in_method_with_ensure
      @executed << :method
      raise EnsureSpec::Error
    ensure
      @executed << :ensure
    end

    def raise_and_rescue_in_method_with_ensure
      @executed << :method
      raise "An Exception"
    rescue
      @executed << :rescue
    ensure
      @executed << :ensure
    end

    def throw_in_method_with_ensure
      @executed << :method
      throw(:symbol)
    ensure
      @executed << :ensure
    end

    def implicit_return_in_method_with_ensure
      :method
    ensure
      :ensure
    end

    def explicit_return_in_method_with_ensure
      return :method
    ensure
      return :ensure
    end

    def explicit_return_in_rescue_and_explicit_return_in_ensure
      raise
    rescue
      return 2
    ensure
      return "returned in ensure"
    end

    def explicit_return_in_rescue_and_implicit_return_in_ensure
      raise
    rescue
      return "returned in rescue"
    ensure
      3
    end

    def raise_and_explicit_return_in_ensure
      raise
    ensure
      return "returned in ensure"
    end

    def raise_in_rescue_and_explicit_return_in_ensure
      raise
    rescue
      raise
    ensure
      return "returned in ensure"
    end

    def raise_in_rescue_and_raise_in_ensure
      raise
    rescue
      raise "raised in rescue"
    ensure
      raise "raised in ensure"
    end

    def raise_in_method_and_raise_in_ensure
      raise
    ensure
      raise "raised in ensure"
    end
  end
end

module EnsureSpec

  class Test

    def initialize
      @values = []
    end

    attr_reader :values

    def call_block
      begin
        @values << :start
        yield
      ensure
        @values << :end
      end
    end

    def do_test
      call_block do
        @values << :in_block
        return :did_test
      end
    end
  end
end

module EnsureSpec
  class Error < RuntimeError
  end
end
