# -*- ruby -*-

require 'dl'
require 'dl/types'

module DL
  module Importable
    LIB_MAP = {}

    module Internal
      def dlload(*libnames)
	if( !defined?(@LIBS) )
	  @LIBS = []
	end
	libnames.each{|libname|
	  if( !LIB_MAP[libname] )
	    LIB_MAP[libname] = DL.dlopen(libname)
	  end
	  @LIBS.push(LIB_MAP[libname])
	}
      end
      alias dllink :dlload

      # example:
      #   extern "int strlen(char*)"
      #
      def extern(proto)
	proto = proto.gsub(/\s+/, " ").strip
	case proto
	when /^([\d\w\*_\s]+)\(([\d\w\*_\s\,\[\]]*)\)$/
	  ret = $1
	  args = $2
	  ret = ret.split(/\s+/)
	  args = args.split(/\s*,\s*/)
	  func = ret.pop
	  ret  = ret.join(" ")
	  return import(func, ret, args)
	else
	  raise(RuntimeError,"can't parse the function prototype: #{proto}")
	end
      end

      # example:
      #   import("get_length", "int", ["void*", "int"])
      #
      def import(name, rettype, argtypes = nil)
	if( !defined?(@SYM) )
	  @SYM   = {}
	end
	@LIBS.each{|lib|
	  rty,_,rdec = encode_type(rettype)
	  ty,enc,dec = encode_types(argtypes)
	  symty = rty + ty

	  begin
	    sym = lib[name, symty]
	  rescue
	    next
	  end

	  mname = name.dup
	  if( ?A <= mname[0] && mname[0] <= ?Z )
	    mname[0,1] = mname[0,1].downcase
	  end
	  @SYM[mname] = [sym,rdec,enc,dec]
	  
	  module_eval [
	    "def #{mname}(*args)",
	    "  sym,rdec,enc,dec  = @SYM['#{mname}']",
	    "  args = enc.call(args) if enc",
	    if( $DEBUG )
	      "  p \"[DL] call #{mname} with \#{args.inspect}\""
	    else
	      ""
	    end,
	    "  r,rs = sym.call(*args)",
	    if( $DEBUG )
	      "  p \"[DL] retval=\#{r.inspect} args=\#{rs.inspect}\""
	    else
	      ""
	    end,
	    "  r  = rdec.call(r) if rdec",
	    "  rs = dec.call(rs) if dec",
	    "  @retval = r",
	    "  @args   = rs",
	    "  return @retval",
	    "end",
	    "module_function :#{mname}",
	  ].join("\n")

	  return @SYM[mname]
	}
	raise(RuntimeError, "can't find #{name}.")
      end

      def _args_
	return @args
      end

      def _retval_
	return @retval
      end
      
      def typealias(ty1, ty2, enc=nil, dec=nil)
	check_type
	@TYDEFS.unshift([ty1,ty2, enc,dec])
      end

      def encode_type(ty)
	check_type
	orig_ty = ty
	enc = nil
	dec = nil
	@TYDEFS.each{|t1,t2,c1,c2|
	  if( t1.is_a?(String) )
	    t1 = Regexp.new("^" + t1 + "$")
	  end
	  if( ty =~ t1 )
	    ty = ty.gsub(t1,t2)
	    if( enc )
	      if( c1 )
		conv1 = enc
		enc = proc{|v| c1.call(conv1.call(v))}
	      end
	    else
	      if( c1 )
		enc = c1
	      end
	    end
	    if( dec )
	      if( c2 )
		conv2 = dec
		dec = proc{|v| c2.call(conv2.call(v))}
	      end
	    else
	      if( c2 )
		dec = c2
	      end
	    end
	  end
	}
	ty = ty.strip
	if( ty.length != 1 )
	  raise(TypeError, "unknown type: #{orig_ty}.")
	end
	return [ty,enc,dec]
      end

      def encode_types(tys)
	encty = []
	enc = nil
	dec = nil
	tys.each_with_index{|ty,idx|
	  ty,c1,c2 = encode_type(ty)
	  encty.push(ty)
	  if( enc )
	    if( c1 )
	      conv1 = enc
	      enc = proc{|v| v = conv1.call(v); v[idx] = c1.call(v[idx]); v}
	    end
	  else
	    if( c1 )
	      enc = proc{|v| v[idx] = c1.call(v[idx]); v}
	    end
	  end
	  if( dec )
	    if( c2 )
	      conv2 = dec
	      dec = proc{|v| v = conv2.call(v); v[idx] = c2.call(v[idx]); v}
	    end
	  else
	    if( c2 )
	      dec = proc{|v| v[idx] = c2.call(v[idx]); v}
	    end
	  end
	}
	return [encty.join, enc, dec]
      end

      def check_type
	if( !defined?(@TYDEFS) )
	  init_type
	end
      end
      
      def init_type
	@TYDEFS = TYPES.collect{|ty| ty[0..3]}
      end
    end # end of Internal
    include Internal
  end # end of Importable
end
