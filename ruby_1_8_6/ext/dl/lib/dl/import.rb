# -*- ruby -*-

require 'dl'
require 'dl/types'

module DL
  module Importable
    LIB_MAP = {}

    module Internal
      def init_types()
	@types ||= ::DL::Types.new
      end

      def init_sym()
	@SYM ||= {}
      end

      def [](name)
	return @SYM[name.to_s][0]
      end

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

      def parse_cproto(proto)
	proto = proto.gsub(/\s+/, " ").strip
	case proto
	when /^([\d\w\*_\s]+)\(([\d\w\*_\s\,\[\]]*)\)$/
	  ret = $1
	  args = $2.strip()
	  ret = ret.split(/\s+/)
	  args = args.split(/\s*,\s*/)
	  func = ret.pop()
	  if( func =~ /^\*/ )
	    func.gsub!(/^\*+/,"")
	    ret.push("*")
	  end
	  ret  = ret.join(" ")
	  return [func, ret, args]
	else
	  raise(RuntimeError,"can't parse the function prototype: #{proto}")
	end
      end

      # example:
      #   extern "int strlen(char*)"
      #
      def extern(proto)
	func,ret,args = parse_cproto(proto)
	return import(func, ret, args)
      end

      # example:
      #   callback "int method_name(int, char*)"
      #
      def callback(proto)
	func,ret,args = parse_cproto(proto)

	init_types()
	init_sym()

	rty,renc,rdec = @types.encode_return_type(ret)
        if( !rty )
          raise(TypeError, "unsupported type: #{ret}")
        end
	ty,enc,dec = encode_argument_types(args)
	symty = rty + ty

	module_eval("module_function :#{func}")
	sym = module_eval([
	  "DL::callback(\"#{symty}\"){|*args|",
	  "  sym,rdec,enc,dec  = @SYM['#{func}']",
	  "  args = enc.call(args) if enc",
	  "  r,rs = #{func}(*args)",
	  "  r  = renc.call(r) if rdec",
	  "  rs = dec.call(rs) if (dec && rs)",
	  "  @retval = r",
	  "  @args   = rs",
	  "  r",
	  "}",
	].join("\n"))

	@SYM[func] = [sym,rdec,enc,dec]

	return sym
      end

      # example:
      #  typealias("uint", "unsigned int")
      #
      def typealias(alias_type, ty1, enc1=nil, dec1=nil, ty2=nil, enc2=nil, dec2=nil)
	init_types()
	@types.typealias(alias_type, ty1, enc1, dec1,
                                     ty2||ty1, enc2, dec2)
      end

      # example:
      #  symbol "foo_value"
      #  symbol "foo_func", "IIP"
      #
      def symbol(name, ty = nil)
	sym = nil
	@LIBS.each{|lib|
	  begin
	    if( ty )
	      sym = lib[name, ty]
	    else
	      sym = lib[name]
	    end
	  rescue
	    next
	  end
	}
	if( !sym )
	  raise(RuntimeError, "can't find the symbol `#{name}'")
	end
	return sym
      end

      # example:
      #   import("get_length", "int", ["void*", "int"])
      #
      def import(name, rettype, argtypes = nil)
	init_types()
	init_sym()

	rty,_,rdec = @types.encode_return_type(rettype)
        if( !rty )
          raise(TypeError, "unsupported type: #{rettype}")
        end
	ty,enc,dec = encode_argument_types(argtypes)
	symty = rty + ty

	sym = symbol(name, symty)

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
	  "  return r",
	  "end",
	  "module_function :#{mname}",
	].join("\n")

	return sym
      end

      def _args_
	return @args
      end

      def _retval_
	return @retval
      end

      def encode_argument_types(tys)
	init_types()
	encty = []
	enc = nil
	dec = nil
	tys.each_with_index{|ty,idx|
	  ty,c1,c2 = @types.encode_argument_type(ty)
          if( !ty )
            raise(TypeError, "unsupported type: #{ty}")
          end
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
    end # end of Internal
    include Internal
  end # end of Importable
end
