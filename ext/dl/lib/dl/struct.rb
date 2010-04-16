# -*- ruby -*-

require 'dl'
require 'dl/import'

module DL
  module Importable
    module Internal
      def define_struct(contents)
	init_types()
	Struct.new(@types, contents)
      end
      alias struct define_struct

      def define_union(contents)
	init_types()
	Union.new(@types, contents)
      end
      alias union define_union

      class Memory
	def initialize(ptr, names, ty, len, enc, dec)
	  @ptr = ptr
	  @names = names
	  @ty    = ty
	  @len   = len
	  @enc   = enc
	  @dec   = dec

	  # define methods
	  @names.each{|name|
	    instance_eval [
	      "def #{name}",
	      "  v = @ptr[\"#{name}\"]",
	      "  if( @len[\"#{name}\"] )",
	      "    v = v.collect{|x| @dec[\"#{name}\"] ? @dec[\"#{name}\"].call(x) : x }",
              "  else",
	      "    v = @dec[\"#{name}\"].call(v) if @dec[\"#{name}\"]",
	      "  end",
	      "  return v",
	      "end",
	      "def #{name}=(v)",
	      "  if( @len[\"#{name}\"] )",
	      "    v = v.collect{|x| @enc[\"#{name}\"] ? @enc[\"#{name}\"].call(x) : x }",
	      "  else",
	      "    v = @enc[\"#{name}\"].call(v) if @enc[\"#{name}\"]",
              "  end",
	      "  @ptr[\"#{name}\"] = v",
	      "  return v",
	      "end",
	    ].join("\n")
	  }
	end

	def to_ptr
	  return @ptr
	end

	def size
	  return @ptr.size
	end
      end

      class Struct
	def initialize(types, contents)
	  @names = []
	  @ty   = {}
	  @len  = {}
	  @enc  = {}
	  @dec  = {}
	  @size = 0
	  @tys  = ""
	  @types = types
	  parse(contents)
	end

	def size
	  return @size
	end

	def members
	  return @names
	end

	# ptr must be a PtrData object.
	def new(ptr)
	  ptr.struct!(@tys, *@names)
	  mem = Memory.new(ptr, @names, @ty, @len, @enc, @dec)
	  return mem
	end

	def malloc(size = nil)
	  if( !size )
	    size = @size
	  end
	  ptr = DL::malloc(size)
	  return new(ptr)
	end

	def parse(contents)
	  contents.each{|elem|
	    name,ty,num,enc,dec = parse_elem(elem)
	    @names.push(name)
	    @ty[name]  = ty
	    @len[name] = num
	    @enc[name] = enc
	    @dec[name] = dec
	    if( num )
	      @tys += "#{ty}#{num}"
	    else
	      @tys += ty
	    end
	  }
	  @size = DL.sizeof(@tys)
	end

	def parse_elem(elem)
	  elem.strip!
	  case elem
	  when /^([\w\d_\*]+)([\*\s]+)([\w\d_]+)$/
	    ty = ($1 + $2).strip
	    name = $3
	    num = nil;
	  when /^([\w\d_\*]+)([\*\s]+)([\w\d_]+)\[(\d+)\]$/
	    ty = ($1 + $2).strip
	    name = $3
	    num = $4.to_i
	  else
	    raise(RuntimeError, "invalid element: #{elem}")
	  end
	  ty,enc,dec = @types.encode_struct_type(ty)
          if( !ty )
            raise(TypeError, "unsupported type: #{ty}")
          end
	  return [name,ty,num,enc,dec]
	end
      end  # class Struct

      class Union < Struct
	def new
	  ptr = DL::malloc(@size)
	  ptr.union!(@tys, *@names)
	  mem = Memory.new(ptr, @names, @ty, @len, @enc, @dec)
	  return mem
	end
      end
    end  # module Internal
  end  # module Importable
end  # module DL
