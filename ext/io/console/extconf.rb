require 'mkmf'

ok = true
hdr = nil
case
when macro_defined?("_WIN32", "")
  have_func("rb_w32_map_errno", "ruby.h")
when hdr = %w"termios.h termio.h".find {|h| have_header(h)}
  have_func("cfmakeraw", hdr)
when have_header(hdr = "sgtty.h")
  %w"stty gtty".each {|f| have_func(f, hdr)}
else
  ok = false
end
ok &&= enable_config("io-console-force-compatible-with-1.8") ||
  macro_defined?("HAVE_RUBY_IO_H", cpp_include("ruby.h"))
if ok
  have_header("sys/ioctl.h")
  have_func("rb_check_hash_type", "ruby.h")
  have_func("rb_io_get_write_io", "ruby/io.h")
  have_func("rb_cloexec_open", "ruby/io.h")
  if enable_config("io-console-rb_scan_args-optional-hash", true)
    $defs << "-DHAVE_RB_SCAN_ARGS_OPTIONAL_HASH=1"
  end
  create_makefile("io/console")
end
