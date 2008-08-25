module DL
  module Win32Types
    def included(m)
      m.module_eval{
        typealias "DWORD", "unsigned long"
        typealias "PDWORD", "unsigned long *"
        typealias "WORD", "unsigned short"
        typealias "PWORD", "unsigned short *"
        typealias "BOOL", "int"
        typealias "ATOM", "int"
        typealias "BYTE", "unsigned char"
        typealias "PBYTE", "unsigned char *"
        typealias "UINT", "unsigned int"
        typealias "ULONG", "unsigned long"
        typealias "UCHAR", "unsigned char"
        typealias "HANDLE", "unsigned long"
        typealias "PHANDLE", "void*"
        typealias "PVOID", "void*"
        typealias "LPCSTR", "char*"
        typealias "LPSTR", "char*"
        typealias "HINSTANCE", "unsigned int"
        typealias "HDC", "unsigned int"
        typealias "HWND", "unsigned int"
      }
    end
    module_function :included
  end

  module BasicTypes
    def included(m)
      m.module_eval{
        typealias "uint", "unsigned int"
        typealias "u_int", "unsigned int"
        typealias "ulong", "unsigned long"
        typealias "u_long", "unsigned long"
      }
    end
    module_function :included
  end
end
