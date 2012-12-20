require 'dl'
require 'dl/callback'
require 'dl/stack'
require 'dl/value'
require 'thread'

module DL
  parent = DL.fiddle? ? Fiddle::Function : Object

  class Function < parent
    include DL
    include ValueUtil

    if DL.fiddle?
      # :stopdoc:
      CALL_TYPE_TO_ABI = Hash.new { |h, k|
        raise RuntimeError, "unsupported call type: #{k}"
      }.merge({ :stdcall => 
                (Fiddle::Function::STDCALL rescue Fiddle::Function::DEFAULT),
                :cdecl   => Fiddle::Function::DEFAULT,
                nil      => Fiddle::Function::DEFAULT
              }).freeze
      private_constant :CALL_TYPE_TO_ABI
      # :startdoc:

      def self.call_type_to_abi(call_type) # :nodoc:
        CALL_TYPE_TO_ABI[call_type]
      end
      private_class_method :call_type_to_abi

      class FiddleClosureCFunc < Fiddle::Closure # :nodoc: all
        def initialize ctype, arg, abi, name
          @name = name
          super(ctype, arg, abi)
        end
        def name
          @name
        end
        def ptr
          to_i
        end
      end
      private_constant :FiddleClosureCFunc

      def self.class_fiddle_closure_cfunc # :nodoc:
        FiddleClosureCFunc
      end
      private_class_method :class_fiddle_closure_cfunc
    end

    def initialize cfunc, argtypes, abi = nil, &block
      if DL.fiddle?
        abi ||= CALL_TYPE_TO_ABI[(cfunc.calltype rescue nil)]
        if block_given?
          @cfunc = Class.new(FiddleClosureCFunc) {
            define_method(:call, block)
          }.new(cfunc.ctype, argtypes, abi, cfunc.name)
        else
          @cfunc  = cfunc
        end

        @args   = argtypes
        super(@cfunc, @args.reject { |x| x == TYPE_VOID }, cfunc.ctype, abi)
      else
        @cfunc = cfunc
        @stack = Stack.new(argtypes.collect{|ty| ty.abs})
        if( @cfunc.ctype < 0 )
          @cfunc.ctype = @cfunc.ctype.abs
          @unsigned = true
        else
          @unsigned = false
        end
        if block_given?
          bind(&block)
        end
      end
    end

    def to_i()
      @cfunc.to_i
    end

    def name
      @cfunc.name
    end

    def call(*args, &block)
      if DL.fiddle?
        if block_given?
          args.find { |a| DL::Function === a }.bind_at_call(&block)
        end
        super
      else
        funcs = []
        _args = wrap_args(args, @stack.types, funcs, &block)
        r = @cfunc.call(@stack.pack(_args))
        funcs.each{|f| f.unbind_at_call()}
        return wrap_result(r)
      end
    end

    def wrap_result(r)
      case @cfunc.ctype
      when TYPE_VOIDP
        r = CPtr.new(r)
      else
        if( @unsigned )
          r = unsigned_value(r, @cfunc.ctype)
        end
      end
      r
    end

    def bind(&block)
      if DL.fiddle?
        @cfunc = Class.new(FiddleClosureCFunc) {
          def initialize ctype, args, abi, name, block
            super(ctype, args, abi, name)
            @block = block
          end

          def call *args
            @block.call(*args)
          end
        }.new(@cfunc.ctype, @args, abi, name, block)
        @ptr = @cfunc
        return nil
      else
        if( !block )
          raise(RuntimeError, "block must be given.")
        end
        if( @cfunc.ptr == 0 )
          cb = Proc.new{|*args|
            ary = @stack.unpack(args)
            @stack.types.each_with_index{|ty, idx|
              case ty
              when TYPE_VOIDP
                ary[idx] = CPtr.new(ary[idx])
              end
            }
            r = block.call(*ary)
            wrap_arg(r, @cfunc.ctype, [])
          }
          case @cfunc.calltype
          when :cdecl
            @cfunc.ptr = set_cdecl_callback(@cfunc.ctype, @stack.size, &cb)
          when :stdcall
            @cfunc.ptr = set_stdcall_callback(@cfunc.ctype, @stack.size, &cb)
          else
            raise(RuntimeError, "unsupported calltype: #{@cfunc.calltype}")
          end
          if( @cfunc.ptr == 0 )
            raise(RuntimeException, "can't bind C function.")
          end
        end
      end
    end

    def unbind()
      if DL.fiddle? then
        if @cfunc.kind_of?(Fiddle::Closure) and @cfunc.ptr != 0 then
          call_type = case abi
                      when CALL_TYPE_TO_ABI[nil]
                        nil
                      when CALL_TYPE_TO_ABI[:stdcall]
                        :stdcall
                      else
                        raise(RuntimeError, "unsupported abi: #{abi}")
                      end
          @cfunc = CFunc.new(0, @cfunc.ctype, name, call_type)
          return 0
        elsif @cfunc.ptr != 0 then
          @cfunc.ptr = 0
          return 0
        else
          return nil
        end
      end
      if( @cfunc.ptr != 0 )
        case @cfunc.calltype
        when :cdecl
          remove_cdecl_callback(@cfunc.ptr, @cfunc.ctype)
        when :stdcall
          remove_stdcall_callback(@cfunc.ptr, @cfunc.ctype)
        else
          raise(RuntimeError, "unsupported calltype: #{@cfunc.calltype}")
        end
        @cfunc.ptr = 0
      end
    end

    def bound?()
      @cfunc.ptr != 0
    end

    def bind_at_call(&block)
      bind(&block)
    end

    def unbind_at_call()
    end
  end

  class TempFunction < Function
    def bind_at_call(&block)
      bind(&block)
    end

    def unbind_at_call()
      unbind()
    end
  end

  class CarriedFunction < Function
    def initialize(cfunc, argtypes, n)
      super(cfunc, argtypes)
      @carrier = []
      @index = n
      @mutex = Mutex.new
    end

    def create_carrier(data)
      ary = []
      userdata = [ary, data]
      @mutex.lock()
      @carrier.push(userdata)
      return dlwrap(userdata)
    end

    def bind_at_call(&block)
      userdata = @carrier[-1]
      userdata[0].push(block)
      bind{|*args|
        ptr = args[@index]
        if( !ptr )
          raise(RuntimeError, "The index of userdata should be lower than #{args.size}.")
        end
        userdata = dlunwrap(Integer(ptr))
        args[@index] = userdata[1]
        userdata[0][0].call(*args)
      }
      @mutex.unlock()
    end
  end
end
