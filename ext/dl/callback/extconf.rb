require 'mkmf'

if compiled?("dl")
  CALLBACKS = (0..8).map{|i| "callback-#{i}"}
  CALLBACK_SRCS = CALLBACKS.map{|basename| "#{basename}.c"}
  CALLBACK_OBJS = CALLBACKS.map{|basename| "#{basename}.o"}

  $distcleanfiles += [ "callback.h", *CALLBACK_SRCS ]

  $objs = %w[ callback.o ] + CALLBACK_OBJS

  $INCFLAGS << " -I$(srcdir)/.."

  create_makefile("dl/callback")
end
