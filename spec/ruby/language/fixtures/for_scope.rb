module ForSpecs
  class ForInClassMethod
    m = :same_variable_set_outside

    def self.foo
      all = []
      for m in [:bar, :baz]
        all << m
      end
      all
    end

    READER = -> { m }
  end
end
