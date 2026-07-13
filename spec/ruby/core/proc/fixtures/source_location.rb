module ProcSpecs
  class SourceLocation
    MY_PROC_LINE = __LINE__ + 2
    def self.my_proc
      proc { true }
    end

    MY_LAMBDA_LINE = __LINE__ + 2
    def self.my_lambda
      -> { true }
    end

    def self.my_block_lambda
      lambda { 42 }
    end

    MY_PROC_NEW_LINE = __LINE__ + 2
    def self.my_proc_new
      Proc.new { true }
    end

    MY_METHOD_LINE = __LINE__ + 1
    def self.my_method
      method(__method__).to_proc
    end

    def self.my_returned_block
      return_block { 42 }
    end

    def self.return_block(&block)
      block
    end

    def self.my_receiver_block
      block_receiver.foo { 42 }
    end

    def self.block_receiver
      obj = Object.new
      def obj.foo(&block)
        block
      end
      obj
    end

    MY_MULTILINE_PROC_LINE = __LINE__ + 2
    def self.my_multiline_proc
      proc do
        'a'.upcase
        1 + 22
      end
    end

    def self.my_heredoc_proc
      proc { <<~END }
        heredoc
      END
    end

    MY_MULTILINE_LAMBDA_LINE = __LINE__ + 2
    def self.my_multiline_lambda
      -> do
        'a'.upcase
        1 + 22
      end
    end

    MY_MULTILINE_PROC_NEW_LINE = __LINE__ + 2
    def self.my_multiline_proc_new
      Proc.new do
        'a'.upcase
        1 + 22
      end
    end

    MY_DETACHED_PROC_LINE = __LINE__ + 2
    def self.my_detached_proc
      body = proc { true }
      proc(&body)
    end

    MY_DETACHED_LAMBDA_LINE = __LINE__ + 2
    def self.my_detached_lambda
      body = -> { true }
      suppress_warning {lambda(&body)}
    end

    MY_DETACHED_PROC_NEW_LINE = __LINE__ + 2
    def self.my_detached_proc_new
      body = Proc.new { true }
      Proc.new(&body)
    end

    iter = Object.new
    def iter.each(&block)
      block.call(block)
    end

    for pr in iter
      42
    end
    MY_FOR_BODY_PROC = pr

    def self.my_for_body_proc
      MY_FOR_BODY_PROC
    end
  end
end
