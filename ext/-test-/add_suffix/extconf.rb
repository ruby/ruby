unless have_func("ruby_add_suffix", "ruby/util.h")
  $INCFLAGS << " -I$(top_srcdir)"
end
create_makefile("-test-/add_suffix/bug")
