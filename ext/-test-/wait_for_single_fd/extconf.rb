# frozen_string_literal: false
headers = %w(sys/types.h sys/time.h sys/event.h).select { |h| have_header(h) }
have_func('kqueue', headers)
create_makefile("-test-/wait_for_single_fd")
