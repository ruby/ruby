# -*- ruby -*-

require 'dl'

module DL
  class Types
    TYPES = [
      # FORMAT:
      # ["alias name", "type name",
      #    encoding_method, decoding_method,   for function prototypes
      #    encoding_method, decoding_method]   for structures (not implemented)
      
      # for Windows
      ["DWORD",  "unsigned long", nil, nil, nil, nil],
      ["PDWORD", "unsigned long *", nil, nil, nil, nil],
      ["WORD",   "unsigned short", nil, nil, nil, nil],
      ["PWORD",  "unsigned int *", nil, nil, nil, nil],
      ["BOOL",   "ibool", nil, nil, nil, nil],
      ["ATOM",   "int", nil, nil, nil, nil],
      ["BYTE",   "unsigned char", nil, nil, nil, nil],
      ["PBYTE",  "unsigned char *", nil, nil, nil, nil],
      ["UINT",   "unsigned int", nil, nil, nil, nil],
      ["ULONG",  "unsigned long", nil, nil, nil, nil],
      ["UCHAR",  "unsigned char", nil, nil, nil, nil],
      ["HANDLE", "unsigned long", nil, nil, nil, nil],
      ["PHANDLE","void*", nil, nil, nil, nil],
      ["PVOID",  "void*", nil, nil, nil, nil],
      ["LPCSTR", "char*", nil, nil, nil, nil],
      ["HDC",    "unsigned int", nil, nil, nil, nil],
      ["HWND",   "unsigned int", nil, nil, nil, nil],
      
      # Others
      ["uint",   "unsigned int", nil, nil, nil, nil],
      ["u_int",  "unsigned int", nil, nil, nil, nil],
      ["ulong",  "unsigned long", nil, nil, nil, nil],
      ["u_long", "unsigned long", nil, nil, nil, nil],
      
      # DL::Importable primitive types
      ["ibool",   "I",
	proc{|v| v ? 1 : 0},
	proc{|v| (v != 0) ? true : false},
	nil, nil],
      ["cbool",   "C",
	proc{|v| v ? 1 : 0},
	proc{|v| (v != 0) ? true : false},
	nil, nil],
      ["lbool",   "L",
	proc{|v| v ? 1 : 0},
	proc{|v| (v != 0) ? true : false},
	nil, nil],
      ["unsigned char", "I",
	proc{|v| [v].pack("C").unpack("c")[0]},
	proc{|v| [v].pack("c").unpack("C")[0]},
	nil, nil],
      ["unsigned short", "H",
	proc{|v| [v].pack("S").unpack("s")[0]},
	proc{|v| [v].pack("s").unpack("S")[0]},
	nil, nil],
      ["unsigned int", "I",
	proc{|v| [v].pack("I").unpack("i")[0]},
	proc{|v| [v].pack("i").unpack("I")[0]},
	nil, nil],
      ["unsigned long", "L",
	proc{|v| [v].pack("L").unpack("l")[0]},
	proc{|v| [v].pack("l").unpack("L")[0]},
	nil, nil],
      ["unsigned char ref", "i",
	proc{|v| [v].pack("C").unpack("c")[0]},
	proc{|v| [v].pack("c").unpack("C")[0]},
	nil, nil],
      ["unsigned int ref", "i",
	proc{|v| [v].pack("I").unpack("i")[0]},
	proc{|v| [v].pack("i").unpack("I")[0]},
	nil, nil],
      ["unsigned long ref", "l",
	proc{|v| [v].pack("L").unpack("l")[0]},
	proc{|v| [v].pack("l").unpack("L")[0]},
	nil, nil],
      ["char ref",  "c", nil, nil, nil, nil],
      ["short ref", "h", nil, nil, nil, nil],
      ["int ref",   "i", nil, nil, nil, nil],
      ["long ref",  "l", nil, nil, nil, nil],
      ["float ref", "f", nil, nil, nil, nil],
      ["double ref","d", nil, nil, nil, nil],
      ["char",   "C", nil, nil, nil, nil],
      ["short",  "H", nil, nil, nil, nil],
      ["int",    "I", nil, nil, nil, nil],
      ["long",   "L", nil, nil, nil, nil],
      ["float",  "F", nil, nil, nil, nil],
      ["double", "D", nil, nil, nil, nil],
      [/char\s*\*/,"S",nil, nil, nil, nil],
      [/.+\*/,   "P", nil, nil, nil, nil],
      [/.+\[\]/, "a", nil, nil, nil, nil],
      ["void",   "0", nil, nil, nil, nil],
    ]

    def initialize
      init_types()
    end

    def typealias(ty1, ty2, enc=nil, dec=nil, senc=nil, sdec=nil)
      @TYDEFS.unshift([ty1,ty2, enc,dec, senc, sdec])
    end

    def init_types
      @TYDEFS = TYPES.dup
    end

    def encode_type(ty)
      orig_ty = ty
      enc = nil
      dec = nil
      senc = nil
      sdec = nil
      @TYDEFS.each{|t1,t2,c1,c2,c3,c4|
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
	  if( senc )
	    if( c3 )
	      conv3 = senc
	      senc = proc{|v| c3.call(conv3.call(v))}
	    end
	  else
	    if( c3 )
	      senc = c3
	    end
	  end
	  if( sdec )
	    if( c4 )
	      conv4 = sdec
	      sdec = proc{|v| c4.call(conv4.call(v))}
	    end
	  else
	    if( c4 )
	      sdec = c4
	    end
	  end
	end
      }
      ty = ty.strip
      if( ty.length != 1 )
	raise(TypeError, "unknown type: #{orig_ty}.")
      end
      return [ty,enc,dec,senc,sdec]
    end
  end # end of Types
end
