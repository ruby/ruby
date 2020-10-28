# frozen_string_literal: false
case RUBY_PLATFORM
when /solaris/i, /linux/i
  $LDFLAGS << " -ldl"
  create_makefile("-test-/popen_deadlock/infinite_loop_dlsym")
end
