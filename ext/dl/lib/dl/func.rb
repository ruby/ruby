require 'dl'
require 'dl/closure'
require 'dl/callback'
require 'dl/stack'
require 'dl/value'
require 'thread'

module DL
  class Function < DL::Method
    include DL
    include ValueUtil

    def initialize cfunc, argtypes, abi = DEFAULT, &block
      if block_given?
        @cfunc = Class.new(DL::Closure) {
          define_method(:call, block)
        }.new(cfunc.ctype, argtypes)
      else
        @cfunc  = cfunc
      end

      @args   = argtypes
      super(@cfunc, @args.reject { |x| x == TYPE_VOID }, cfunc.ctype, abi)
    end

    def to_i()
      @cfunc.to_i
    end

    def name
      @cfunc.name
    end

    def call(*args, &block)
      if block_given?
        args.find { |a| DL::Function === a }.bind_at_call(&block)
      end
      super
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
      @cfunc = Class.new(DL::Closure) {
        def initialize ctype, args, block
          super(ctype, args)
          @block = block
        end

        def call *args
          @block.call(*args)
        end
      }.new(@cfunc.ctype, @args, block)
    end

    def unbind()
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
