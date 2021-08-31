module DelegationSpecs
  class Target
    def target(*args, **kwargs)
      [args, kwargs]
    end

    def target_block(*args, **kwargs)
      yield [kwargs, args]
    end
  end
end
