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
      [/^.+\*$/,   "P", nil, nil,
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

    def encode_argument_type(alias_type)
      proc_encode = nil
      proc_decode = nil
      @TYDEFS.each{|aty,ty,enc,dec,_,_,_|
	if( (aty.is_a?(Regexp) && (aty =~ alias_type)) || (aty == alias_type) )
	  alias_type = alias_type.gsub(aty,ty) if ty
          alias_type.strip! if alias_type
	  if( proc_encode )
	    if( enc )
	      conv1 = proc_encode
	      proc_encode = proc{|v| enc.call(conv1.call(v))}
	    end
	  else
	    if( enc )
	      proc_encode = enc
	    end
	  end
	  if( proc_decode )
	    if( dec )
	      conv2 = proc_decode
	      proc_decode = proc{|v| dec.call(conv2.call(v))}
	    end
	  else
	    if( dec )
	      proc_decode = dec
	    end
	  end
	end
      }
      return [alias_type, proc_encode, proc_decode]
    end

    def encode_return_type(ty)
      ty, enc, dec = encode_argument_type(ty)
      return [ty, enc, dec]
    end

    def encode_struct_type(alias_type)
      proc_encode = nil
      proc_decode = nil
      @TYDEFS.each{|aty,_,_,_,ty,enc,dec|
	if( (aty.is_a?(Regexp) && (aty =~ alias_type)) || (aty == alias_type) )
	  alias_type = alias_type.gsub(aty,ty) if ty
          alias_type.strip! if alias_type
	  if( proc_encode )
	    if( enc )
	      conv1 = proc_encode
	      proc_encode = proc{|v| enc.call(conv1.call(v))}
	    end
	  else
	    if( enc )
	      proc_encode = enc
	    end
	  end
	  if( proc_decode )
	    if( dec )
	      conv2 = proc_decode
	      proc_decode = proc{|v| dec.call(conv2.call(v))}
	    end
	  else
	    if( dec )
	      proc_decode = dec
	    end
	  end
	end
      }
      return [alias_type, proc_encode, proc_decode]
    end
  end # end of Types
end
