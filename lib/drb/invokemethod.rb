
# for ruby-1.8.0

module DRb
  class DRbServer
    module InvokeMethod18Mixin
      def block_yield(x)
        block_value = @block.call(*x)
      end
      
      def rescue_break(err)
        return :break, err.exit_value
      end
      
      def perform_with_block
        @obj.__send__(@msg_id, *@argv) do |*x|
          jump_error = nil
          begin
            block_value = block_yield(x)
          rescue LocalJumpError
            jump_error = $!
          end
          if jump_error
            reason, jump_value = rescue_local_jump(jump_error)
            case reason
            when :retry
              retry
            when :break
              break(jump_value)
            else
              raise jump_error
            end
          end
          block_value
        end
      end
    end
  end
end
