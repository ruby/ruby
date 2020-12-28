# frozen_string_literal: true
module Fiddle
  # Adds Windows type aliases to the including class for use with
  # Fiddle::Importer.
  #
  # The aliases added are:
  # * ATOM
  # * BOOL
  # * BYTE
  # * DWORD
  # * DWORD32
  # * DWORD64
  # * HANDLE
  # * HDC
  # * HINSTANCE
  # * HWND
  # * LPCSTR
  # * LPSTR
  # * PBYTE
  # * PDWORD
  # * PHANDLE
  # * PVOID
  # * PWORD
  # * UCHAR
  # * UINT
  # * ULONG
  # * WORD
  module Win32Types
    def included(m) # :nodoc:
      # https://docs.microsoft.com/en-us/windows/win32/winprog/windows-data-types
      m.module_eval{
        typealias "DWORD", "unsigned long"
        typealias "PDWORD", "DWORD *"
        typealias "DWORD32", "uint32_t"
        typealias "DWORD64", "uint64_t"
        typealias "WORD", "unsigned short"
        typealias "PWORD", "WORD *"
        typealias "BOOL", "int"
        typealias "ATOM", "WORD"
        typealias "BYTE", "unsigned char"
        typealias "PBYTE", "BYTE *"
        typealias "UINT", "unsigned int"
        typealias "ULONG", "unsigned long"
        typealias "UCHAR", "unsigned char"
        typealias "HANDLE", "PVOID"
        typealias "PHANDLE", "HANDLE *"
        typealias "PVOID", "void *"
        typealias "LPCSTR", "const char *"
        typealias "LPSTR", "char *"
        typealias "HINSTANCE", "HANDLE"
        typealias "HDC", "HANDLE"
        typealias "HWND", "HANDLE"
      }
    end
    module_function :included
  end

  # Adds basic type aliases to the including class for use with Fiddle::Importer.
  #
  # The aliases added are +uint+ and +u_int+ (<tt>unsigned int</tt>) and
  # +ulong+ and +u_long+ (<tt>unsigned long</tt>)
  module BasicTypes
    def included(m) # :nodoc:
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
