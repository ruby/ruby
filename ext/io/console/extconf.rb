# frozen_string_literal: false
require 'mkmf'

# `--target-rbconfig` compatibility for Ruby 3.3 or earlier
# See https://bugs.ruby-lang.org/issues/20345
MakeMakefile::RbConfig ||= ::RbConfig

have_func("rb_interned_str_cstr") # Ruby 3.0
have_func("rb_ractor_local_storage_value_newkey") # Ruby 3.0
have_func("rb_io_descriptor", "ruby/io.h") # Ruby 3.1
have_func("rb_io_path", "ruby/io.h") # Ruby 3.3
have_func("rb_io_closed_p", "ruby/io.h") # Ruby 3.3
have_func("rb_io_open_descriptor", "ruby/io.h") # Ruby 3.3

is_wasi = /wasi/ =~ MakeMakefile::RbConfig::CONFIG["platform"]
# `ok` can be `true`, `false`, or `nil`:
#   * `true` : Required headers and functions available, proceed regular build.
#   * `false`: Required headers or functions not available, abort build.
#   * `nil`  : Unsupported compilation target, generate dummy Makefile.
#
# Skip building io/console on WASI, as it does not support termios.h.
ok = true if (RUBY_ENGINE == "ruby" && !is_wasi) || RUBY_ENGINE == "truffleruby"
hdr = nil
case
when macro_defined?("_WIN32", "")
  win32 = true
  # rb_w32_map_errno: 1.8.7
  vk_header = File.exist?("#$srcdir/win32_vk.list") ? "chksum" : "inc"
  vk_header = "#{'{$(srcdir)}' if $nmake == ?m}win32_vk.#{vk_header}"
when hdr = %w"termios.h termio.h".find {|h| have_header(h)}
  have_func("cfmakeraw", hdr)
when have_header(hdr = "sgtty.h")
  %w"stty gtty".each {|f| have_func(f, hdr)}
else
  ok = false
end if ok
case ok
when true
  have_header("sys/ioctl.h") if hdr
  # rb_check_hash_type: 1.9.3
  # rb_io_get_write_io: 1.9.1
  # rb_cloexec_open: 2.0.0
  # rb_funcallv: 2.1.0
  # RARRAY_CONST_PTR: 2.1.0
  # rb_sym2str: 2.2.0
  if have_macro("HAVE_RUBY_FIBER_SCHEDULER_H")
    $defs << "-D""HAVE_RB_IO_WAIT=1"
  elsif have_func("rb_scheduler_timeout") # Ruby 3.0 (internal)
    have_func("rb_io_wait") # Ruby 3.0
  end
  have_func("rb_category_warn")
  have_const("RB_WARN_CATEGORY_DEPRECATED")
  win32 or have_func("ttyname_r") or have_func("ttyname")
  have_func("rb_prepend_module") # not exported by TruffleRuby
  vk_tool = find_executable("gperf")
  create_makefile("io/console") {|conf|
    if vk_header
      conf << <<~MK
        VK_HEADER = #{vk_header}
        all:
        console.#$OBJEXT: $(VK_HEADER)
      MK
    end
    if vk_tool
      unless conf.any? {|c| /^ *top_srcdir *=/.match?(c)}
        conf << "top_srcdir = $(srcdir)/../../..\n"
      end
      conf.concat(depend_rules(File.read("#$srcdir/win32_vk.mk")))
    end
    conf
  }
when nil
  File.write("Makefile", dummy_makefile($srcdir).join(""))
end
