# -*- ruby -*-

require 'dl'

module DL
  TYPES = [
    # FORMAT:
    # ["alias name", "type name",
    #    encoding_method, decoding_method,   for function prototypes
    #    encoding_method, decoding_method]   for structures (not implemented)

    # for Windows
    ["DWORD",  "unsigned long", nil, nil, nil, nil],
    ["PDWORD", "unsigned long *", nil, nil, nil, nil],
    ["WORD",   "unsigned int", nil, nil, nil, nil],
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
    [/.+\*/,   "P", nil, nil, nil, nil],
    [/.+\[\]/, "a", nil, nil, nil, nil],
    ["void",   "0", nil, nil, nil, nil],
  ]
end
