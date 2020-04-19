require "ruby/signature/test/spy"
require "ruby/signature/test/errors"
require "ruby/signature/test/type_check"
require "ruby/signature/test/hook"

module Ruby
  module Signature
    module Test
      IS_AP = Kernel.instance_method(:is_a?)
      DEFINE_METHOD = Module.instance_method(:define_method)
      INSTANCE_EVAL = BasicObject.instance_method(:instance_eval)
      INSTANCE_EXEC = BasicObject.instance_method(:instance_exec)
      METHOD = Kernel.instance_method(:method)
      CLASS = Kernel.instance_method(:class)
      SINGLETON_CLASS = Kernel.instance_method(:singleton_class)
      PP = Kernel.instance_method(:pp)
      INSPECT = Kernel.instance_method(:inspect)
      METHODS = Kernel.instance_method(:methods)

      ArgumentsReturn = Struct.new(:arguments, :return_value, :exception, keyword_init: true)
      CallTrace = Struct.new(:method_name, :method_call, :block_calls, :block_given, keyword_init: true)

      def self.call(receiver, method, *args, **kwargs, &block)
        method.bind_call(receiver, *args, **kwargs, &block)
      end
    end
  end
end
