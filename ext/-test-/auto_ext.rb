# frozen_string_literal: false
def auto_ext(feat = $0[%r[/ext/(-test-/.*)/extconf.rb\z], 1], inc: false)
  $INCFLAGS << " -I$(topdir) -I$(top_srcdir)" if inc
  $srcs = Dir[File.join($srcdir, "*.{#{SRC_EXT.join(%q{,})}}")]
  inits = $srcs.map {|s| File.basename(s, ".*")}
  inits.delete("init")
  inits.map! {|s|"X(#{s})"}
  $defs << "-DTEST_INIT_FUNCS(X)=\"#{inits.join(' ')}\""
  create_header
  create_makefile(feat)
end
