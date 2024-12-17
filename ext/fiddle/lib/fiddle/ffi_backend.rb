# This is based on JRuby's FFI-based fiddle implementation.

require 'ffi'

module Fiddle
  def self.malloc(size)
    Fiddle::Pointer.malloc(size)
  end

  def self.free(ptr)
    Fiddle::Pointer::LibC::FREE.call(ptr)
    nil
  end

  def self.dlwrap(val)
    Pointer.to_ptr(val)
  end

  module Types
    VOID         = 0
    VOIDP        = 1
    CHAR         = 2
    UCHAR        = -CHAR
    SHORT        = 3
    USHORT       = -SHORT
    INT          = 4
    UINT         = -INT
    LONG         = 5
    ULONG        = -LONG
    LONG_LONG    = 6
    ULONG_LONG   = -LONG_LONG
    FLOAT        = 7
    DOUBLE       = 8
    VARIADIC     = 9
    CONST_STRING = 10
    BOOL         = 11
    INT8_T       = CHAR
    UINT8_T      = UCHAR
    if FFI::Type::Builtin::SHORT.size == 2
      INT16_T    = SHORT
      UINT16_T   = USHORT
    elsif FFI::Type::Builtin::INT.size == 2
      INT16_T    = INT
      UINT16_T   = UINT
    end
    if FFI::Type::Builtin::SHORT.size == 4
      INT32_T    = SHORT
      UINT32_T   = USHORT
    elsif FFI::Type::Builtin::INT.size == 4
      INT32_T    = INT
      UINT32_T   = UINT
    elsif FFI::Type::Builtin::LONG.size == 4
      INT32_T    = LONG
      UINT32_T   = ULONG
    end
    if FFI::Type::Builtin::INT.size == 8
      INT64_T    = INT
      UINT64_T   = UINT
    elsif FFI::Type::Builtin::LONG.size == 8
      INT64_T    = LONG
      UINT64_T   = ULONG
    else
      INT64_T    = LONG_LONG
      UINT64_T   = ULONG_LONG
    end

    # FIXME: platform specific values
    SSIZE_T      = INT64_T
    SIZE_T       = -SSIZE_T
    PTRDIFF_T    = SSIZE_T
    INTPTR_T     = INT64_T
    UINTPTR_T    = -INTPTR_T
  end

  WINDOWS = FFI::Platform.windows?

  module FFIBackend
    FFITypes = {
        'c' => FFI::Type::INT8,
        'h' => FFI::Type::INT16,
        'i' => FFI::Type::INT32,
        'l' => FFI::Type::LONG,
        'f' => FFI::Type::FLOAT32,
        'd' => FFI::Type::FLOAT64,
        'p' => FFI::Type::POINTER,
        's' => FFI::Type::STRING,

        Types::VOID => FFI::Type::Builtin::VOID,
        Types::VOIDP => FFI::Type::Builtin::POINTER,
        Types::CHAR => FFI::Type::Builtin::CHAR,
        Types::UCHAR => FFI::Type::Builtin::UCHAR,
        Types::SHORT => FFI::Type::Builtin::SHORT,
        Types::USHORT => FFI::Type::Builtin::USHORT,
        Types::INT => FFI::Type::Builtin::INT,
        Types::UINT => FFI::Type::Builtin::UINT,
        Types::LONG => FFI::Type::Builtin::LONG,
        Types::ULONG => FFI::Type::Builtin::ULONG,
        Types::LONG_LONG => FFI::Type::Builtin::LONG_LONG,
        Types::ULONG_LONG => FFI::Type::Builtin::ULONG_LONG,
        Types::FLOAT => FFI::Type::Builtin::FLOAT,
        Types::DOUBLE => FFI::Type::Builtin::DOUBLE,
        Types::BOOL => FFI::Type::Builtin::BOOL,
        Types::CONST_STRING => FFI::Type::Builtin::POINTER,
        Types::VARIADIC => FFI::Type::Builtin::VARARGS,
    }

    def self.to_ffi_type(fiddle_type)
      if fiddle_type.is_a?(Symbol)
        fiddle_type = Types.const_get(fiddle_type.to_s.upcase)
      end
      if !fiddle_type.is_a?(Integer) && fiddle_type.respond_to?(:to_int)
        fiddle_type = fiddle_type.to_int
      end
      ffi_type = FFITypes[fiddle_type]
      ffi_type = FFITypes[-fiddle_type] if ffi_type.nil? && fiddle_type.is_a?(Integer) && fiddle_type < 0
      raise TypeError.new("cannot convert #{fiddle_type} to ffi") unless ffi_type
      ffi_type
    end
  end

  class Function
    DEFAULT = "default"
    STDCALL = "stdcall"

    def initialize(ptr, args, return_type, abi = DEFAULT, kwargs = nil)
      if kwargs.nil?
        if abi.kind_of? Hash
          kwargs = abi
          abi = DEFAULT
        end
      end
      @name = kwargs[:name] if kwargs.kind_of? Hash
      @ptr, @args, @return_type, @abi = ptr, args, return_type, abi
      raise TypeError.new "invalid argument types" unless args.is_a?(Array)

      ffi_return_type = Fiddle::FFIBackend.to_ffi_type(@return_type)
      ffi_args = @args.map { |t| Fiddle::FFIBackend.to_ffi_type(t) }
      pointer = FFI::Pointer.new(ptr.to_i)
      options = {convention: @abi}
      if ffi_args.last == FFI::Type::Builtin::VARARGS
        @function = FFI::VariadicInvoker.new(
          pointer,
          ffi_args,
          ffi_return_type,
          options
        )
      else
        @function = FFI::Function.new(ffi_return_type, ffi_args, pointer, options)
      end
    end

    def call(*args, &block)
      if @function.is_a?(FFI::VariadicInvoker)
        n_fixed_args = @args.size - 1
        n_fixed_args.step(args.size - 1, 2) do |i|
          if args[i] == :const_string || args[i] == Types::CONST_STRING
            args[i + 1] = String.try_convert(args[i + 1]) || args[i + 1]
          end
          args[i] = Fiddle::FFIBackend.to_ffi_type(args[i])
        end
      else
        @args.each_with_index do |arg_type, i|
          next unless arg_type == Types::VOIDP

          src = args[i]
          next if src.nil?
          next if src.is_a?(String)
          next if src.is_a?(FFI::AbstractMemory)
          next if src.is_a?(FFI::Struct)

          args[i] = Pointer[src]
        end
      end
      result = @function.call(*args, &block)
      result = Pointer.new(result) if result.is_a?(FFI::Pointer)
      result
    end
  end

  class Closure
    def initialize(ret, args, abi = Function::DEFAULT)
      raise TypeError.new "invalid argument types" unless args.is_a?(Array)

      @ctype, @args = ret, args
      ffi_args = @args.map { |t| Fiddle::FFIBackend.to_ffi_type(t) }
      if ffi_args.size == 1 && ffi_args[0] == FFI::Type::Builtin::VOID
        ffi_args = []
      end
      return_type = Fiddle::FFIBackend.to_ffi_type(@ctype)
      raise "#{self.class} must implement #call" unless respond_to?(:call)
      callable = method(:call)
      @function = FFI::Function.new(return_type, ffi_args, callable, convention: abi)
      @freed = false
    end

    def to_ptr
      @function
    end

    def to_i
      @function.to_i
    end

    def free
      return if @freed
      @function.free
      @freed = true
    end

    def freed?
      @freed
    end
  end

  class Error < StandardError; end
  class DLError < Error; end
  class ClearedReferenceError < Error; end

  class Pointer
    attr_reader :ffi_ptr
    extend FFI::DataConverter
    native_type FFI::Type::Builtin::POINTER

    def self.to_native(value, ctx)
      if value.is_a?(Pointer)
        value.ffi_ptr

      elsif value.is_a?(Integer)
        FFI::Pointer.new(value)

      elsif value.is_a?(String)
        value
      end
    end

    def self.from_native(value, ctx)
      self.new(value)
    end

    def self.to_ptr(value)
      if value.is_a?(String)
        cptr = Pointer.malloc(value.bytesize)
        cptr.ffi_ptr.put_string(0, value)
        cptr

      elsif value.is_a?(Array)
        raise NotImplementedError, "array ptr"

      elsif value.respond_to?(:to_ptr)
        ptr = value.to_ptr
        case ptr
        when Pointer
          ptr
        when FFI::Pointer
          Pointer.new(ptr)
        else
          raise DLError.new("to_ptr should return a Fiddle::Pointer object, was #{ptr.class}")
        end

      else
        Pointer.new(value)
      end
    end

    def self.write(addr, bytes)
      FFI::Pointer.new(addr).write_bytes(bytes)
    end

    def self.read(addr, len)
      FFI::Pointer.new(addr).read_bytes(len)
    end

    class << self
      alias [] to_ptr
    end

    def []=(*args, value)
      if args.size == 2
        if value.is_a?(Integer)
          value = self.class.new(value)
        end
        if value.is_a?(Fiddle::Pointer)
          value = value.to_str(args[1])
        end

        @ffi_ptr.put_bytes(args[0], value, 0, args[1])
      elsif args.size == 1
        if value.is_a?(Fiddle::Pointer)
          value = value.to_str(args[0] + 1)
        else
          value = value.chr
        end

        @ffi_ptr.put_bytes(args[0], value, 0, 1)
      end
    rescue FFI::NullPointerError
      raise DLError.new("NULL pointer access")
    end

    def initialize(addr, size = nil, free = nil)
      ptr = if addr.is_a?(FFI::Pointer)
              addr

            elsif addr.is_a?(Integer)
              FFI::Pointer.new(addr)

            elsif addr.respond_to?(:to_ptr)
              fiddle_ptr = addr.to_ptr
              if fiddle_ptr.is_a?(Pointer)
                fiddle_ptr.ffi_ptr
              elsif fiddle_ptr.is_a?(FFI::AutoPointer)
                addr.ffi_ptr
              elsif fiddle_ptr.is_a?(FFI::Pointer)
                fiddle_ptr
              else
                raise DLError.new("to_ptr should return a Fiddle::Pointer object, was #{fiddle_ptr.class}")
              end
            elsif addr.is_a?(IO)
              raise NotImplementedError, "IO ptr isn't supported"
            else
              FFI::Pointer.new(Integer(addr))
            end

      @size = size ? size : ptr.size
      @free = free
      @ffi_ptr = ptr
      @freed = false
    end

    module LibC
      extend FFI::Library
      ffi_lib FFI::Library::LIBC
      MALLOC = attach_function :malloc, [ :size_t ], :pointer
      REALLOC = attach_function :realloc, [ :pointer, :size_t ], :pointer
      FREE = attach_function :free, [ :pointer ], :void
    end

    def self.malloc(size, free = nil)
      if block_given? and free.nil?
        message = "a free function must be supplied to #{self}.malloc " +
                  "when it is called with a block"
        raise ArgumentError, message
      end

      pointer = new(LibC.malloc(size), size, free)
      if block_given?
        begin
          yield(pointer)
        ensure
          pointer.call_free
        end
      else
        pointer
      end
    end

    def null?
      @ffi_ptr.null?
    end

    def to_ptr
      @ffi_ptr
    end

    def size
      defined?(@layout) ? @layout.size : @size
    end

    def free
      @free
    end

    def free=(free)
      @free = free
    end

    def call_free
      return if @free.nil?
      return if @freed
      if @free == RUBY_FREE
        LibC::FREE.call(@ffi_ptr)
      else
        @free.call(@ffi_ptr)
      end
      @freed = true
    end

    def freed?
      @freed
    end

    def size=(size)
      @size = size
    end

    def [](index, length = nil)
      if length
        ffi_ptr.get_bytes(index, length)
      else
        ffi_ptr.get_char(index)
      end
    rescue FFI::NullPointerError
      raise DLError.new("NULL pointer dereference")
    end

    def to_i
      ffi_ptr.to_i
    end
    alias to_int to_i

    # without \0
    def to_s(len = nil)
      if len
        ffi_ptr.get_string(0, len)
      else
        ffi_ptr.get_string(0)
      end
    rescue FFI::NullPointerError
      raise DLError.new("NULL pointer access")
    end

    def to_str(len = nil)
      if len
        ffi_ptr.read_string(len)
      else
        ffi_ptr.read_string(@size)
      end
    rescue FFI::NullPointerError
      raise DLError.new("NULL pointer access")
    end

    def to_value
      raise NotImplementedError, "to_value isn't supported"
    end

    def inspect
      "#<#{self.class.name} ptr=#{to_i.to_s(16)} size=#{@size} free=#{@free.inspect}>"
    end

    def +(delta)
      self.class.new(to_i + delta, @size - delta)
    end

    def -(delta)
      self.class.new(to_i - delta, @size + delta)
    end

    def <=>(other)
      return unless other.is_a?(Pointer)
      diff = self.to_i - other.to_i
      return 0 if diff == 0
      diff > 0 ? 1 : -1
    end

    def eql?(other)
      return unless other.is_a?(Pointer)
      self.to_i == other.to_i
    end

    def ==(other)
      eql?(other)
    end

    def ptr
      Pointer.new(ffi_ptr.get_pointer(0))
    end

    def +@
      ptr
    end

    def -@
      ref
    end

    def ref
      cptr = Pointer.malloc(FFI::Type::POINTER.size, RUBY_FREE)
      cptr.ffi_ptr.put_pointer(0, ffi_ptr)
      cptr
    end
  end

  class Handle
    RTLD_GLOBAL = FFI::DynamicLibrary::RTLD_GLOBAL
    RTLD_LAZY = FFI::DynamicLibrary::RTLD_LAZY
    RTLD_NOW = FFI::DynamicLibrary::RTLD_NOW

    def initialize(libname = nil, flags = RTLD_LAZY | RTLD_GLOBAL)
      begin
        @lib = FFI::DynamicLibrary.open(libname, flags)
      rescue LoadError, RuntimeError # LoadError for JRuby, RuntimeError for TruffleRuby
        raise DLError, "Could not open #{libname}"
      end

      @open = true

      begin
        yield(self)
      ensure
        self.close
      end if block_given?
    end

    def close
      raise DLError.new("closed handle") unless @open
      @open = false
      0
    end

    def self.sym(func)
      DEFAULT.sym(func)
    end

    def sym(func)
      raise TypeError.new("invalid function name") unless func.is_a?(String)
      raise DLError.new("closed handle") unless @open
      address = @lib.find_function(func)
      raise DLError.new("unknown symbol #{func}") if address.nil? || address.null?
      address.to_i
    end

    def self.sym_defined?(func)
      DEFAULT.sym_defined?(func)
    end

    def sym_defined?(func)
      raise TypeError.new("invalid function name") unless func.is_a?(String)
      raise DLError.new("closed handle") unless @open
      address = @lib.find_function(func)
      !address.nil? && !address.null?
    end

    def self.[](func)
      self.sym(func)
    end

    def [](func)
      sym(func)
    end

    def enable_close
      @enable_close = true
    end

    def close_enabled?
      @enable_close
    end

    def disable_close
      @enable_close = false
    end

    DEFAULT = new
  end

  class Pinned
    def initialize(object)
      @object = object
    end

    def ref
      if @object.nil?
        raise ClearedReferenceError, "`ref` called on a cleared object"
      end
      @object
    end

    def clear
      @object = nil
    end

    def cleared?
      @object.nil?
    end
  end

  RUBY_FREE = Fiddle::Pointer::LibC::FREE.address
  NULL = Fiddle::Pointer.new(0)

  ALIGN_VOIDP       = Fiddle::FFIBackend::FFITypes[Types::VOIDP].alignment
  ALIGN_CHAR        = Fiddle::FFIBackend::FFITypes[Types::CHAR].alignment
  ALIGN_SHORT       = Fiddle::FFIBackend::FFITypes[Types::SHORT].alignment
  ALIGN_INT         = Fiddle::FFIBackend::FFITypes[Types::INT].alignment
  ALIGN_LONG        = Fiddle::FFIBackend::FFITypes[Types::LONG].alignment
  ALIGN_LONG_LONG   = Fiddle::FFIBackend::FFITypes[Types::LONG_LONG].alignment
  ALIGN_INT8_T      = Fiddle::FFIBackend::FFITypes[Types::INT8_T].alignment
  ALIGN_INT16_T     = Fiddle::FFIBackend::FFITypes[Types::INT16_T].alignment
  ALIGN_INT32_T     = Fiddle::FFIBackend::FFITypes[Types::INT32_T].alignment
  ALIGN_INT64_T     = Fiddle::FFIBackend::FFITypes[Types::INT64_T].alignment
  ALIGN_FLOAT       = Fiddle::FFIBackend::FFITypes[Types::FLOAT].alignment
  ALIGN_DOUBLE      = Fiddle::FFIBackend::FFITypes[Types::DOUBLE].alignment
  ALIGN_BOOL        = Fiddle::FFIBackend::FFITypes[Types::BOOL].alignment
  ALIGN_SIZE_T      = Fiddle::FFIBackend::FFITypes[Types::SIZE_T].alignment
  ALIGN_SSIZE_T     = ALIGN_SIZE_T
  ALIGN_PTRDIFF_T   = Fiddle::FFIBackend::FFITypes[Types::PTRDIFF_T].alignment
  ALIGN_INTPTR_T    = Fiddle::FFIBackend::FFITypes[Types::INTPTR_T].alignment
  ALIGN_UINTPTR_T   = Fiddle::FFIBackend::FFITypes[Types::UINTPTR_T].alignment

  SIZEOF_VOIDP       = Fiddle::FFIBackend::FFITypes[Types::VOIDP].size
  SIZEOF_CHAR        = Fiddle::FFIBackend::FFITypes[Types::CHAR].size
  SIZEOF_UCHAR       = Fiddle::FFIBackend::FFITypes[Types::UCHAR].size
  SIZEOF_SHORT       = Fiddle::FFIBackend::FFITypes[Types::SHORT].size
  SIZEOF_USHORT      = Fiddle::FFIBackend::FFITypes[Types::USHORT].size
  SIZEOF_INT         = Fiddle::FFIBackend::FFITypes[Types::INT].size
  SIZEOF_UINT        = Fiddle::FFIBackend::FFITypes[Types::UINT].size
  SIZEOF_LONG        = Fiddle::FFIBackend::FFITypes[Types::LONG].size
  SIZEOF_ULONG       = Fiddle::FFIBackend::FFITypes[Types::ULONG].size
  SIZEOF_LONG_LONG   = Fiddle::FFIBackend::FFITypes[Types::LONG_LONG].size
  SIZEOF_ULONG_LONG  = Fiddle::FFIBackend::FFITypes[Types::ULONG_LONG].size
  SIZEOF_INT8_T      = Fiddle::FFIBackend::FFITypes[Types::INT8_T].size
  SIZEOF_UINT8_T     = Fiddle::FFIBackend::FFITypes[Types::UINT8_T].size
  SIZEOF_INT16_T     = Fiddle::FFIBackend::FFITypes[Types::INT16_T].size
  SIZEOF_UINT16_T    = Fiddle::FFIBackend::FFITypes[Types::UINT16_T].size
  SIZEOF_INT32_T     = Fiddle::FFIBackend::FFITypes[Types::INT32_T].size
  SIZEOF_UINT32_T    = Fiddle::FFIBackend::FFITypes[Types::UINT32_T].size
  SIZEOF_INT64_T     = Fiddle::FFIBackend::FFITypes[Types::INT64_T].size
  SIZEOF_UINT64_T    = Fiddle::FFIBackend::FFITypes[Types::UINT64_T].size
  SIZEOF_FLOAT       = Fiddle::FFIBackend::FFITypes[Types::FLOAT].size
  SIZEOF_DOUBLE      = Fiddle::FFIBackend::FFITypes[Types::DOUBLE].size
  SIZEOF_BOOL        = Fiddle::FFIBackend::FFITypes[Types::BOOL].size
  SIZEOF_SIZE_T      = Fiddle::FFIBackend::FFITypes[Types::SIZE_T].size
  SIZEOF_SSIZE_T     = SIZEOF_SIZE_T
  SIZEOF_PTRDIFF_T   = Fiddle::FFIBackend::FFITypes[Types::PTRDIFF_T].size
  SIZEOF_INTPTR_T    = Fiddle::FFIBackend::FFITypes[Types::INTPTR_T].size
  SIZEOF_UINTPTR_T   = Fiddle::FFIBackend::FFITypes[Types::UINTPTR_T].size
  SIZEOF_CONST_STRING = Fiddle::FFIBackend::FFITypes[Types::VOIDP].size
end
