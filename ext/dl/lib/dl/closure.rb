require 'dl'

module DL
  class Closure
    attr_reader :ctype
    attr_reader :args

    class BlockCaller < DL::Closure
      def initialize ctype, args, abi = DL::Function::DEFAULT, &block
        super(ctype, args, abi)
        @block = block
      end

      def call *args
        @block.call(*args)
      end
    end
  end
end
