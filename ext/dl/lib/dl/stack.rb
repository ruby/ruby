require 'dl'

module DL
  class Stack
    def Stack.[](*types)
      Stack.new(types)
    end

    def initialize(types)
      parse_types(types)
    end

    def size()
      @size
    end

    def types()
      @types
    end

    def pack(ary)
      case SIZEOF_VOIDP
      when SIZEOF_LONG
        ary.pack(@template).unpack('l!*')
      when SIZEOF_LONG_LONG
        ary.pack(@template).unpack('q*')
      else
        raise(RuntimeError, "sizeof(void*)?")
      end
    end

    def unpack(ary)
      case SIZEOF_VOIDP
      when SIZEOF_LONG
        ary.pack('l!*').unpack(@template)
      when SIZEOF_LONG_LONG
        ary.pack('q*').unpack(@template)
      else
        raise(RuntimeError, "sizeof(void*)?")
      end
    end
    
    private
    
    def align(addr, align)
      d = addr % align
      if( d == 0 )
        addr
      else
        addr + (align - d)
      end
    end

if( defined?(TYPE_LONG_LONG) )
    ALIGN_MAP = {
      TYPE_VOIDP => ALIGN_VOIDP,
      TYPE_CHAR  => ALIGN_VOIDP,
      TYPE_SHORT => ALIGN_VOIDP,
      TYPE_INT   => ALIGN_VOIDP,
      TYPE_LONG  => ALIGN_VOIDP,
      TYPE_LONG_LONG => ALIGN_LONG_LONG,
      TYPE_FLOAT => ALIGN_FLOAT,
      TYPE_DOUBLE => ALIGN_DOUBLE,
    }

    PACK_MAP = {
      TYPE_VOIDP => ((SIZEOF_VOIDP == SIZEOF_LONG_LONG)? "q" : "l!"),
      TYPE_CHAR  => "c",
      TYPE_SHORT => "s!",
      TYPE_INT   => "i!",
      TYPE_LONG  => "l!",
      TYPE_LONG_LONG => "q",
      TYPE_FLOAT => "f",
      TYPE_DOUBLE => "d",
    }

    SIZE_MAP = {
      TYPE_VOIDP => SIZEOF_VOIDP,
      TYPE_CHAR  => SIZEOF_CHAR,
      TYPE_SHORT => SIZEOF_SHORT,
      TYPE_INT   => SIZEOF_INT,
      TYPE_LONG  => SIZEOF_LONG,
      TYPE_LONG_LONG => SIZEOF_LONG_LONG,
      TYPE_FLOAT => SIZEOF_FLOAT,
      TYPE_DOUBLE => SIZEOF_DOUBLE,
    }
else
    ALIGN_MAP = {
      TYPE_VOIDP => ALIGN_VOIDP,
      TYPE_CHAR  => ALIGN_VOIDP,
      TYPE_SHORT => ALIGN_VOIDP,
      TYPE_INT   => ALIGN_VOIDP,
      TYPE_LONG  => ALIGN_VOIDP,
      TYPE_FLOAT => ALIGN_FLOAT,
      TYPE_DOUBLE => ALIGN_DOUBLE,
    }

    PACK_MAP = {
      TYPE_VOIDP => ((SIZEOF_VOIDP == SIZEOF_LONG_LONG)? "q" : "l!"),
      TYPE_CHAR  => "c",
      TYPE_SHORT => "s!",
      TYPE_INT   => "i!",
      TYPE_LONG  => "l!",
      TYPE_FLOAT => "f",
      TYPE_DOUBLE => "d",
    }

    SIZE_MAP = {
      TYPE_VOIDP => SIZEOF_VOIDP,
      TYPE_CHAR  => SIZEOF_CHAR,
      TYPE_SHORT => SIZEOF_SHORT,
      TYPE_INT   => SIZEOF_INT,
      TYPE_LONG  => SIZEOF_LONG,
      TYPE_FLOAT => SIZEOF_FLOAT,
      TYPE_DOUBLE => SIZEOF_DOUBLE,
    }
end

    def parse_types(types)
      @types = types
      @template = ""
      addr      = 0
      types.each{|t|
        orig_addr = addr
        addr = align(orig_addr, ALIGN_MAP[t])
        d = addr - orig_addr
        if( d > 0 )
          @template << "x#{d}"
        end
        @template << PACK_MAP[t]
        addr += SIZE_MAP[t]
      }
      if( addr % SIZEOF_VOIDP == 0 )
        @size = addr / SIZEOF_VOIDP
      else
        @size = (addr / SIZEOF_VOIDP) + 1
      end
    end
  end
end
