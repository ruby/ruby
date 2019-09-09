# frozen_string_literal: false

cfg = RbConfig::CONFIG.merge(
  'hdrdir'      => $hdrdir.quote,
  'src'         => "#{CONFTEST_C}",
  'arch_hdrdir' => $arch_hdrdir.quote,
  'top_srcdir'  => $top_srcdir.quote,
  'CC'          => RbConfig::CONFIG['CXX'],
  'CFLAGS'      => RbConfig::CONFIG['CXXFLAGS'],
  'INCFLAGS'    => "#$INCFLAGS",
  'CPPFLAGS'    => "#$CPPFLAGS",
  'ARCH_FLAG'   => "#$ARCH_FLAG",
  'LDFLAGS'     => "#$LDFLAGS",
  'LOCAL_LIBS'  => "#$LOCAL_LIBS",
  'LIBS'        => "#$LIBS"
)
cxx = RbConfig::expand(TRY_LINK.dup, cfg)
src = create_tmpsrc(<<~'begin') do |x|
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

begin
  create_makefile("-test-/cxxanyargs") if xsystem(cxx)
ensure
  log_src src
end
