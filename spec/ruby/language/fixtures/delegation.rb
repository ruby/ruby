module DelegationSpecs
  class Target
    def target(*args, **kwargs, &block)
      [args, kwargs, block]
    end

    def target_block(*args, **kwargs)
      yield [kwargs, args]
    end
  end
end
