# -*- ruby -*-

require 'dl'

module DL
  class Types
    TYPES = [
      # FORMAT:
      # ["alias name",
      #  "type name", encoding_method, decoding_method,   for function prototypes
      #  "type name", encoding_method, decoding_method]   for structures (not implemented)
      
      # for Windows
      ["DWORD",  "unsigned long", nil, nil,
                 "unsigned long", nil, nil],
      ["PDWORD", "unsigned long *", nil, nil,
                 "unsigned long *", nil, nil],
      ["WORD",   "unsigned short", nil, nil,
                 "unsigned short", nil, nil],
      ["PWORD",  "unsigned int *", nil, nil,
                 "unsigned int *", nil, nil],
      ["BYTE",   "unsigned char",   nil, nil,
                 "unsigned char", nil, nil],
      ["PBYTE",  "unsigned char *", nil, nil,
                 "unsigned char *", nil, nil],
      ["BOOL",   "ibool", nil, nil,
                 "ibool", nil, nil],
      ["ATOM",   "int", nil, nil,
                 "int", nil, nil],
      ["BYTE",   "unsigned char", nil, nil,
                 "unsigned char", nil, nil],
      ["PBYTE",  "unsigned char *", nil, nil,
                 "unsigned char *", nil, nil],
      ["UINT",   "unsigned int", nil, nil,
                 "unsigned int", nil, nil],
      ["ULONG",  "unsigned long", nil, nil,
                 "unsigned long", nil, nil],
      ["UCHAR",  "unsigned char", nil, nil,
                 "unsigned char", nil, nil],
      ["HANDLE", "unsigned long", nil, nil,
                 "unsigned long", nil, nil],
      ["PHANDLE","void*", nil, nil,
                 "void*", nil, nil],
      ["PVOID",  "void*", nil, nil,
                 "void*", nil, nil],
      ["LPCSTR", "char*", nil, nil,
                 "char*", nil, nil],
      ["HDC",    "unsigned int", nil, nil,
                 "unsigned int", nil, nil],
      ["HWND",   "unsigned int", nil, nil,
                 "unsigned int", nil, nil],
      
      # Others
      ["uint",   "unsigned int", nil, nil,
                 "unsigned int", nil, nil],
      ["u_int",  "unsigned int", nil, nil,
                 "unsigned int", nil, nil],
      ["ulong",  "unsigned long", nil, nil,
                 "unsigned long", nil, nil],
      ["u_long", "unsigned long", nil, nil,
                 "unsigned long", nil, nil],

      # DL::Importable primitive types
      ["ibool",
        "I",
	proc{|v| v ? 1 : 0},
	proc{|v| (v != 0) ? true : false},
        "I",
	proc{|v| v ? 1 : 0 },
	proc{|v| (v != 0) ? true : false} ],
      ["cbool",
        "C",
	proc{|v| v ? 1 : 0},
	proc{|v| (v != 0) ? true : false},
        "C",
	proc{|v,len| v ? 1 : 0},
	proc{|v,len| (v != 0) ? true : false}],
      ["lbool",
        "L",
	proc{|v| v ? 1 : 0},
	proc{|v| (v != 0) ? true : false},
        "L",
	proc{|v,len| v ? 1 : 0},
	proc{|v,len| (v != 0) ? true : false}],
      ["unsigned char",
        "C",
	proc{|v| [v].pack("C").unpack("c")[0]},
	proc{|v| [v].pack("c").unpack("C")[0]},
        "C",
	proc{|v| [v].pack("C").unpack("c")[0]},
	proc{|v| [v].pack("c").unpack("C")[0]}],
      ["unsigned short",
        "H",
	proc{|v| [v].pack("S").unpack("s")[0]},
	proc{|v| [v].pack("s").unpack("S")[0]},
        "H",
	proc{|v| [v].pack("S").unpack("s")[0]},
	proc{|v| [v].pack("s").unpack("S")[0]}],
      ["unsigned int",
        "I",
	proc{|v| [v].pack("I").unpack("i")[0]},
	proc{|v| [v].pack("i").unpack("I")[0]},
        "I",
	proc{|v| [v].pack("I").unpack("i")[0]},
	proc{|v| [v].pack("i").unpack("I")[0]}],
      ["unsigned long",
        "L",
	proc{|v| [v].pack("L").unpack("l")[0]},
	proc{|v| [v].pack("l").unpack("L")[0]},
        "L",
	proc{|v| [v].pack("L").unpack("l")[0]},
	proc{|v| [v].pack("l").unpack("L")[0]}],
      ["unsigned char ref",
        "c",
	proc{|v| [v].pack("C").unpack("c")[0]},
	proc{|v| [v].pack("c").unpack("C")[0]},
	nil, nil, nil],
      ["unsigned int ref",
        "i",
	proc{|v| [v].pack("I").unpack("i")[0]},
	proc{|v| [v].pack("i").unpack("I")[0]},
	nil, nil, nil],
      ["unsigned long ref",
        "l",
	proc{|v| [v].pack("L").unpack("l")[0]},
	proc{|v| [v].pack("l").unpack("L")[0]},
	nil, nil, nil],
      ["char ref",  "c", nil, nil,
                    nil, nil, nil],
      ["short ref", "h", nil, nil,
                    nil, nil, nil],
      ["int ref",   "i", nil, nil,
                    nil, nil, nil],
      ["long ref",  "l", nil, nil,
                    nil, nil, nil],
      ["float ref", "f", nil, nil,
                    nil, nil, nil],
      ["double ref","d", nil, nil,
                    nil, nil, nil],
      ["char",   "C", nil, nil,
                 "C", nil, nil],
      ["short",  "H", nil, nil,
                 "H", nil, nil],
      ["int",    "I", nil, nil,
                 "I", nil, nil],
      ["long",   "L", nil, nil,
                 "L", nil, nil],
      ["float",  "F", nil, nil,
                 "F", nil, nil],
      ["double", "D", nil, nil,
                 "D", nil, nil],
      [/^char\s*\*$/,"s",nil, nil,
                     "S",nil, nil],
      [/^const char\s*\*$/,"S",nil, nil,
                           "S",nil, nil],
      [/^.+\*$/,   "p", nil, nil,
                   "P", nil, nil],
      [/^.+\[\]$/, "a", nil, nil,
                   "a", nil, nil],
      ["void",   "0", nil, nil,
                 nil, nil, nil],
    ]

    def initialize
      init_types()
    end

    def typealias(ty1, ty2, enc=nil, dec=nil, ty3=nil, senc=nil, sdec=nil)
      @TYDEFS.unshift([ty1, ty2, enc, dec, ty3, senc, sdec])
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
      ty1 = nil
      ty2 = nil
      @TYDEFS.each{|t1,t2,c1,c2,t3,c3,c4|
#	if( t1.is_a?(String) )
#	  t1 = Regexp.new("^" + t1 + "$")
#	end
	if( (t1.is_a?(Regexp) && (t1 =~ ty)) || (t1 == ty) )
	  ty1 = ty.gsub(t1,t2)
          ty2 = ty.gsub(t1,t3)
          ty1.strip! if ty1
          ty2.strip! if ty2
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
      if( ty1.length != 1 && ty2.length != 1 )
	raise(TypeError, "unknown type: #{orig_ty}.")
      end
      return [ty1,enc,dec,ty2,senc,sdec]
    end
  end # end of Types
end
