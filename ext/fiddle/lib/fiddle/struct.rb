# frozen_string_literal: false
require 'fiddle'
require 'fiddle/value'
require 'fiddle/pack'

module Fiddle
  # C struct shell
  class CStruct
    # accessor to Fiddle::CStructEntity
    def CStruct.entity_class
      CStructEntity
    end
  end

  # C union shell
  class CUnion
    # accessor to Fiddle::CUnionEntity
    def CUnion.entity_class
      CUnionEntity
    end
  end

  # Used to construct C classes (CUnion, CStruct, etc)
  #
  # Fiddle::Importer#struct and Fiddle::Importer#union wrap this functionality in an
  # easy-to-use manner.
  module CStructBuilder
    # Construct a new class given a C:
    # * class +klass+ (CUnion, CStruct, or other that provide an
    #   #entity_class)
    # * +types+ (Fiddle::TYPE_INT, Fiddle::TYPE_SIZE_T, etc., see the C types
    #   constants)
    # * corresponding +members+
    #
    # Fiddle::Importer#struct and Fiddle::Importer#union wrap this functionality in an
    # easy-to-use manner.
    #
    # Example:
    #
    #   require 'fiddle/struct'
    #   require 'fiddle/cparser'
    #
    #   include Fiddle::CParser
    #
    #   types, members = parse_struct_signature(['int i','char c'])
    #
    #   MyStruct = Fiddle::CStructBuilder.create(Fiddle::CUnion, types, members)
    #
    #   obj = MyStruct.allocate
    #
    def create(klass, types, members)
      new_class = Class.new(klass){
        define_method(:initialize){|addr|
          @entity = klass.entity_class.new(addr, types)
          @entity.assign_names(members)
        }
        define_method(:to_ptr){ @entity }
        define_method(:to_i){ @entity.to_i }
        members.each{|name|
          define_method(name){ @entity[name] }
          define_method(name + "="){|val| @entity[name] = val }
        }
      }
      size = klass.entity_class.size(types)
      new_class.module_eval(<<-EOS, __FILE__, __LINE__+1)
        def new_class.size()
          #{size}
        end
        def new_class.malloc()
          addr = Fiddle.malloc(#{size})
          new(addr)
        end
      EOS
      return new_class
    end
    module_function :create
  end

  # A C struct wrapper
  class CStructEntity < Fiddle::Pointer
    include PackInfo
    include ValueUtil

    # Allocates a C struct with the +types+ provided.
    #
    # When the instance is garbage collected, the C function +func+ is called.
    def CStructEntity.malloc(types, func = nil)
      addr = Fiddle.malloc(CStructEntity.size(types))
      CStructEntity.new(addr, types, func)
    end

    # Returns the offset for the packed sizes for the given +types+.
    #
    #   Fiddle::CStructEntity.size(
    #     [ Fiddle::TYPE_DOUBLE,
    #       Fiddle::TYPE_INT,
    #       Fiddle::TYPE_CHAR,
    #       Fiddle::TYPE_VOIDP ]) #=> 24
    def CStructEntity.size(types)
      offset = 0

      max_align = types.map { |type, count = 1|
        last_offset = offset

        align = PackInfo::ALIGN_MAP[type]
        offset = PackInfo.align(last_offset, align) +
                 (PackInfo::SIZE_MAP[type] * count)

        align
      }.max

      PackInfo.align(offset, max_align)
    end

    # Wraps the C pointer +addr+ as a C struct with the given +types+.
    #
    # When the instance is garbage collected, the C function +func+ is called.
    #
    # See also Fiddle::Pointer.new
    def initialize(addr, types, func = nil)
      set_ctypes(types)
      super(addr, @size, func)
    end

    # Set the names of the +members+ in this C struct
    def assign_names(members)
      @members = members
    end

    # Calculates the offsets and sizes for the given +types+ in the struct.
    def set_ctypes(types)
      @ctypes = types
      @offset = []
      offset = 0

      max_align = types.map { |type, count = 1|
        orig_offset = offset
        align = ALIGN_MAP[type]
        offset = PackInfo.align(orig_offset, align)

        @offset << offset

        offset += (SIZE_MAP[type] * count)

        align
      }.max

      @size = PackInfo.align(offset, max_align)
    end

    # Fetch struct member +name+
    def [](name)
      idx = @members.index(name)
      if( idx.nil? )
        raise(ArgumentError, "no such member: #{name}")
      end
      ty = @ctypes[idx]
      if( ty.is_a?(Array) )
        r = super(@offset[idx], SIZE_MAP[ty[0]] * ty[1])
      else
        r = super(@offset[idx], SIZE_MAP[ty.abs])
      end
      packer = Packer.new([ty])
      val = packer.unpack([r])
      case ty
      when Array
        case ty[0]
        when TYPE_VOIDP
          val = val.collect{|v| Pointer.new(v)}
        end
      when TYPE_VOIDP
        val = Pointer.new(val[0])
      else
        val = val[0]
      end
      if( ty.is_a?(Integer) && (ty < 0) )
        return unsigned_value(val, ty)
      elsif( ty.is_a?(Array) && (ty[0] < 0) )
        return val.collect{|v| unsigned_value(v,ty[0])}
      else
        return val
      end
    end

    # Set struct member +name+, to value +val+
    def []=(name, val)
      idx = @members.index(name)
      if( idx.nil? )
        raise(ArgumentError, "no such member: #{name}")
      end
      ty  = @ctypes[idx]
      packer = Packer.new([ty])
      val = wrap_arg(val, ty, [])
      buff = packer.pack([val].flatten())
      super(@offset[idx], buff.size, buff)
      if( ty.is_a?(Integer) && (ty < 0) )
        return unsigned_value(val, ty)
      elsif( ty.is_a?(Array) && (ty[0] < 0) )
        return val.collect{|v| unsigned_value(v,ty[0])}
      else
        return val
      end
    end

    def to_s() # :nodoc:
      super(@size)
    end
  end

  # A C union wrapper
  class CUnionEntity < CStructEntity
    include PackInfo

    # Allocates a C union the +types+ provided.
    #
    # When the instance is garbage collected, the C function +func+ is called.
    def CUnionEntity.malloc(types, func=nil)
      addr = Fiddle.malloc(CUnionEntity.size(types))
      CUnionEntity.new(addr, types, func)
    end

    # Returns the size needed for the union with the given +types+.
    #
    #   Fiddle::CUnionEntity.size(
    #     [ Fiddle::TYPE_DOUBLE,
    #       Fiddle::TYPE_INT,
    #       Fiddle::TYPE_CHAR,
    #       Fiddle::TYPE_VOIDP ]) #=> 8
    def CUnionEntity.size(types)
      types.map { |type, count = 1|
        PackInfo::SIZE_MAP[type] * count
      }.max
    end

    # Calculate the necessary offset and for each union member with the given
    # +types+
    def set_ctypes(types)
      @ctypes = types
      @offset = Array.new(types.length, 0)
      @size   = self.class.size types
    end
  end
end

