module Fiddle
  class Closure
    attr_reader :ctype
    attr_reader :args

    class BlockCaller < Fiddle::Closure
      def initialize ctype, args, abi = Fiddle::Function::DEFAULT, &block
        super(ctype, args, abi)
        @block = block
      end

      def call *args
        @block.call(*args)
      end
    end
  end
end
