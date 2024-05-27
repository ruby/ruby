#
#  Under compilers with WERRORFLAG, MakeMakefile.try_compile treats warnings as errors, so we can
#  use append_cflags to test whether the public header files emit warnings with certain flags turned
#  on.
#
def check_append_cflags(flag, msg = nil)
  msg ||= "flag #{flag} is not acceptable"
  !$CFLAGS.include?(flag) or raise("flag #{flag} already present in $CFLAGS")
  append_cflags(flag)
  $CFLAGS.include?(flag) or raise(msg)
end

if %w[gcc clang].include?(RbConfig::CONFIG['CC'])
  config_string("WERRORFLAG") or raise("expected WERRORFLAG to be defined")

  # should be acceptable on all modern C compilers
  check_append_cflags("-D_TEST_OK", "baseline compiler warning test failed")

  # Feature #20507: Allow compilation of C extensions with -Wconversion
  check_append_cflags("-Wconversion", "-Wconversion raising warnings in public headers")
end

create_makefile("-test-/public_header_warnings")
