# frozen_string_literal: false

cxx = MakeMakefile["C++"]

ok = cxx.try_compile(<<~'begin', "") do |x|
  #include "ruby/config.h"

  namespace {
      typedef int conftest[SIZEOF_LONG == sizeof(long) ? 1 : -1];
      typedef int conftest[SIZEOF_VOIDP == sizeof(void*) ? 1 : -1];
  }

  int
  main(int argc, const char** argv)
  {
      return !!argv[argc];
  }
begin
  # We are wiping ruby.h from the source because that header file is the
  # subject we are going to test in this extension library.
  x.sub! %<#include "ruby.h">, ''
end

if ok
  $srcs = %w[cxxanyargs.cpp]
  $cleanfiles << "failure.failed"
  create_makefile("-test-/cxxanyargs") do |mk|
    mk << <<MK

cxxanyargs.#$OBJEXT: failure.failed

failure.failed: failure.cpp
\t$(Q)$(RUBY) -rfileutils \\
\t  -e "err = IO.popen(%[$(MAKE) failure.#$OBJEXT], err:[:child, :out], &:read)" \\
\t  -e "abort err unless /rb_define_method/ =~ err" \\
\t  -e "FileUtils.touch(*ARGV)" $@
MK
  end
end
