require "dl/import"
require "dl/struct"

module LIBC
  extend DL::Importable

  begin
    dlload "libc.so.6"
  rescue
    dlload "libc.so.5"
  end

  extern "int atoi(char*)"
  extern "ibool isdigit(int)"
  extern "int gettimeofday(struct timeval *, struct timezone *)"
  extern "char* strcat(char*, char*)"
  extern "FILE* fopen(char*, char*)"
  extern "int fclose(FILE*)"
  extern "int fgetc(FILE*)"
  extern "int strlen(char*)"
  extern "void qsort(void*, int, int, void*)"

  def str_qsort(ary, comp)
    len = ary.length
    r,rs = qsort(ary, len, DL.sizeof('P'), comp)
    return rs[0].to_a('S', len)
  end

  Timeval = struct [
    "long tv_sec",
    "long tv_usec",
  ]

  Timezone = struct [
    "int tz_minuteswest",
    "int tz_dsttime",
  ]

  def my_compare(ptr1, ptr2)
    ptr1.ptr.to_s <=> ptr2.ptr.to_s
  end
  COMPARE = callback("int my_compare(char**, char**)")
end


$cb1 = DL.callback('IPP'){|ptr1, ptr2|
  str1 = ptr1.ptr.to_s
  str2 = ptr2.ptr.to_s
  str1 <=> str2
}

p LIBC.atoi("10")

p LIBC.isdigit(?1)

p LIBC.isdigit(?a)

p LIBC.strcat("a", "b")

ary = ["a","c","b"]
ptr = ary.to_ptr
LIBC.qsort(ptr, ary.length, DL.sizeof('P'), LIBC::COMPARE)
p ptr.to_a('S', ary.length)

tv = LIBC::Timeval.malloc
tz = LIBC::Timezone.malloc
LIBC.gettimeofday(tv, tz)

p Time.at(tv.tv_sec)
