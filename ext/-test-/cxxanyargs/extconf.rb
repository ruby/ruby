# frozen_string_literal: false

cxx = MakeMakefile["C++"]

# #### have_devel hack ####
# cxx.try_compile tries to detect compilers, but the try_compile below is
# trying to detect a compiler in a different way.  We need to prevent the
# default detection routine.

cxx.instance_variable_set(:'@have_devel', true)

ok = cxx.try_link(<<~'begin', "") do |x|
  #include "ruby/config.h"

  namespace {
      typedef int conftest1[SIZEOF_LONG == sizeof(long) ? 1 : -1];
      typedef int conftest2[SIZEOF_VOIDP == sizeof(void*) ? 1 : -1];
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

cxx.instance_variable_set(:'@have_devel', ok)

if ok
  $srcs = %w[cxxanyargs.cpp]
  failures = Dir.glob($srcdir + "/failure*.cpp").map {|n| File.basename(n)}
  $cleanfiles << "$(FAILURES:.cpp=.failed)"
  create_makefile("-test-/cxxanyargs") do |mk|
    mk << "FAILURES #{['=', failures].join(' ')}\n"
    mk << ".IGNORE: $(FAILURES:.cpp=.o)\n" unless $mswin
    mk
  end
end
