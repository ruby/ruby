# frozen_string_literal: false

cxx = MakeMakefile::CXX

ok = cxx.try_compile(<<~'begin', "", lang: 'C++') do |x|
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
  create_makefile("-test-/cxxanyargs")
end
