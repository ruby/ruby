# frozen_string_literal: false
case RUBY_PLATFORM when /mingw/ then
  # skip
else
  headers = %w(sys/types.h sys/time.h sys/event.h).select { |h| have_header(h) }
  have_func('kqueue', headers)
end
create_makefile("-test-/wait_for_single_fd")
