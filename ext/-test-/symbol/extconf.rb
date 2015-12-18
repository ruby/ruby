# frozen_string_literal: false
$srcs = Dir[File.join($srcdir, "*.{#{SRC_EXT.join(%q{,})}}")]
inits = $srcs.map {|s| File.basename(s, ".*")}
inits.delete("init")
inits.map! {|s|"X(#{s})"}
$defs << "-DTEST_INIT_FUNCS(X)=\"#{inits.join(' ')}\""
have_func("rb_pin_dynamic_symbol")
create_makefile("-test-/symbol")
