# -*- mode: makefile-gmake; indent-tabs-mode: t -*-

# Show Cargo progress when doing `make V=1`
CARGO_VERBOSE_0 = -q
CARGO_VERBOSE_1 =
CARGO_VERBOSE = $(CARGO_VERBOSE_$(V))

ZJIT_SRC_FILES = $(wildcard \
	$(top_srcdir)/zjit/Cargo.* \
	$(top_srcdir)/zjit/src/*.rs \
	$(top_srcdir)/zjit/src/*/*.rs \
	$(top_srcdir)/zjit/src/*/*/*.rs \
	$(top_srcdir)/zjit/src/*/*/*/*.rs \
	)

# Because of Cargo cache, if the actual binary is not changed from the
# previous build, the mtime is preserved as the cached file.
# This means the target is not updated actually, and it will need to
# rebuild at the next build.
ZJIT_LIB_TOUCH = touch $@

# Absolute path to match RUST_LIB rules to avoid picking
# the "target" dir in the source directory through VPATH.
BUILD_ZJIT_LIBS = $(TOP_BUILD_DIR)/$(ZJIT_LIBS)

# ZJIT_SUPPORT=yes when `configure` gets `--enable-zjit`
ifeq ($(ZJIT_SUPPORT),yes)
$(BUILD_ZJIT_LIBS): $(ZJIT_SRC_FILES)
	$(ECHO) 'building Rust ZJIT (release mode)'
	+$(Q) $(RUSTC) $(ZJIT_RUSTC_ARGS)
	$(ZJIT_LIB_TOUCH)
endif

ifneq ($(ZJIT_SUPPORT),no)
$(RUST_LIB): $(ZJIT_SRC_FILES)
endif

# By using ZJIT_BENCH_OPTS instead of RUN_OPTS, you can skip passing the options to `make install`
ZJIT_BENCH_OPTS = $(RUN_OPTS) --enable-gems
ZJIT_BENCH = benchmarks/railsbench/benchmark.rb

# Run zjit-bench's ./run_once.sh for CI
zjit-bench: install update-zjit-bench PHONY
	$(Q) cd $(srcdir)/zjit-bench && PATH=$(prefix)/bin:$$PATH \
		./run_once.sh $(ZJIT_BENCH_OPTS) $(ZJIT_BENCH)

update-zjit-bench:
	$(Q) $(tooldir)/git-refresh -C $(srcdir) --branch main \
		https://github.com/Shopify/zjit-bench zjit-bench $(GIT_OPTS)

# List of test files to exclude for ZJIT
ZJIT_EXCLUDED_TESTS = \
	test/ruby/bug-11928.rb \
	test/ruby/namespace/call_toplevel.rb \
	test/ruby/namespace/current.rb \
	test/ruby/namespace/ns.rb \
	test/ruby/namespace/raise.rb \
	test/ruby/namespace/string_ext_calling.rb \
	test/ruby/namespace/string_ext_eval_caller.rb \
	test/ruby/test_alias.rb \
	test/ruby/test_allocation.rb \
	test/ruby/test_ast.rb \
	test/ruby/test_autoload.rb \
	test/ruby/test_backtrace.rb \
	test/ruby/test_beginendblock.rb \
	test/ruby/test_call.rb \
	test/ruby/test_class.rb \
	test/ruby/test_compile_prism.rb \
	test/ruby/test_complex.rb \
	test/ruby/test_data.rb \
	test/ruby/test_defined.rb \
	test/ruby/test_dir_m17n.rb \
	test/ruby/test_env.rb \
	test/ruby/test_enumerator.rb \
	test/ruby/test_exception.rb \
	test/ruby/test_fiber.rb \
	test/ruby/test_file.rb \
	test/ruby/test_file_exhaustive.rb \
	test/ruby/test_float.rb \
	test/ruby/test_gc.rb \
	test/ruby/test_hash.rb \
	test/ruby/test_io.rb \
	test/ruby/test_iseq.rb \
	test/ruby/test_keyword.rb \
	test/ruby/test_lambda.rb \
	test/ruby/test_literal.rb \
	test/ruby/test_marshal.rb \
	test/ruby/test_memory_view.rb \
	test/ruby/test_method.rb \
	test/ruby/test_module.rb \
	test/ruby/test_namespace.rb \
	test/ruby/test_object.rb \
	test/ruby/test_object_id.rb \
	test/ruby/test_objectspace.rb \
	test/ruby/test_optimization.rb \
	test/ruby/test_parse.rb \
	test/ruby/test_proc.rb \
	test/ruby/test_process.rb \
	test/ruby/test_ractor.rb \
	test/ruby/test_range.rb \
	test/ruby/test_rational.rb \
	test/ruby/test_regexp.rb \
	test/ruby/test_rubyoptions.rb \
	test/ruby/test_set.rb \
	test/ruby/test_settracefunc.rb \
	test/ruby/test_super.rb \
	test/ruby/test_string.rb \
	test/ruby/test_struct.rb \
	test/ruby/test_symbol.rb \
	test/ruby/test_syntax.rb \
	test/ruby/test_thread.rb \
	test/ruby/test_time_tz.rb \
	test/ruby/test_variable.rb \
	test/ruby/test_vm_dump.rb \
	test/ruby/test_yjit.rb

# Get all test files in test/ruby directory
ZJIT_ALL_RUBY_TESTS := $(wildcard $(top_srcdir)/test/ruby/*.rb $(top_srcdir)/test/ruby/*/*.rb)

# Filter out excluded tests
ZJIT_RUBY_TESTS := $(filter-out $(addprefix $(top_srcdir)/,$(ZJIT_EXCLUDED_TESTS)),$(ZJIT_ALL_RUBY_TESTS))

# Run all Ruby tests with ZJIT enabled (temporarily excluding known failing tests)
.PHONY: zjit-test-ruby-all
zjit-test-ruby-all:
	$(MAKE) test-all TESTS='$(ZJIT_RUBY_TESTS)'

# Run only the ZJIT-specific Ruby tests
.PHONY: zjit-test-ruby
zjit-test-ruby:
	$(MAKE) test-all TESTS='$(top_srcdir)/test/ruby/test_zjit.rb'

# Gives quick feedback about ZJIT. Not a replacement for a full test run.
.PHONY: zjit-test-suite
zjit-test-suite:
	$(MAKE) zjit-test-rust
	$(MAKE) zjit-test-ruby
ZJIT_BINDGEN_DIFF_OPTS =

# Generate Rust bindings. See source for details.
# Needs `./configure --enable-zjit=dev` and Clang.
ifneq ($(strip $(CARGO)),) # if configure found Cargo
.PHONY: zjit-bindgen zjit-bindgen-show-unused zjit-test-rust zjit-test-rust-lldb
zjit-bindgen: zjit.$(OBJEXT)
	ZJIT_SRC_ROOT_PATH='$(top_srcdir)' BINDGEN_JIT_NAME=zjit $(CARGO) run --manifest-path '$(top_srcdir)/zjit/bindgen/Cargo.toml' -- $(CFLAGS) $(XCFLAGS) $(CPPFLAGS)
	$(Q) if [ 'x$(HAVE_GIT)' = xyes ]; then $(GIT) -C "$(top_srcdir)" diff $(ZJIT_BINDGEN_DIFF_OPTS) zjit/src/cruby_bindings.inc.rs; fi

# We need `cargo nextest` for its one-process-per execution execution model
# since we can only boot the VM once per process. Normal `cargo test`
# runs tests in threads and can't handle this.
#
# On darwin, it's available through `brew install cargo-nextest`. See
# https://nexte.st/docs/installation/pre-built-binaries/ otherwise.
zjit-test-rust: libminiruby.a
	RUBY_BUILD_DIR='$(TOP_BUILD_DIR)' \
	    RUBY_LD_FLAGS='$(LDFLAGS) $(XLDFLAGS) $(MAINLIBS)' \
	    CARGO_TARGET_DIR='$(CARGO_TARGET_DIR)' \
	    $(CARGO) nextest run --manifest-path '$(top_srcdir)/zjit/Cargo.toml' $(ZJIT_TESTS)

# Run a ZJIT test written with Rust #[test] under LLDB
zjit-test-rust-lldb: libminiruby.a
	$(Q)set -eu; \
	    if [ -z '$(ZJIT_TESTS)' ]; then \
		echo "Please pass a ZJIT_TESTS=... filter to make."; \
		echo "Many tests only work when it's the only test in the process."; \
		exit 1; \
	    fi; \
	    exe_path=`RUBY_BUILD_DIR='$(TOP_BUILD_DIR)' \
	    RUBY_LD_FLAGS='$(LDFLAGS) $(XLDFLAGS) $(MAINLIBS)' \
	    CARGO_TARGET_DIR='$(CARGO_TARGET_DIR)' \
	    $(CARGO) nextest list --manifest-path '$(top_srcdir)/zjit/Cargo.toml' --message-format json --list-type=binaries-only | \
	    $(BASERUBY) -rjson -e 'puts JSON.load(STDIN.read).dig("rust-binaries", "zjit", "binary-path")'`; \
	    exec lldb $$exe_path -- --test-threads=1 $(ZJIT_TESTS)

# A library for booting miniruby in tests.
# Why not use libruby-static.a for this?
#  - Initialization of the full ruby involves dynamic linking for e.g. transcoding implementations
#    our tests don't need these functionalities so good to avoid their complexity.
#  - By being mini, it's faster to build
#  - Less likely to break since later stages of the build process also rely on miniruby.
libminiruby.a: miniruby$(EXEEXT)
	$(ECHO) linking static-library $@
	$(Q) $(AR) $(ARFLAGS) $@ $(MINIOBJS) $(COMMONOBJS)

libminiruby: libminiruby.a
endif
