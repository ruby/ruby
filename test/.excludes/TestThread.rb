# frozen_string_literal: false
exclude(/_stack_size$/, 'often too expensive')
if /mswin/ =~ RUBY_PLATFORM && ENV.key?('GITHUB_ACTIONS')
  # to avoid "`failed to allocate memory (NoMemoryError)" error
  exclude(:test_thread_interrupt_for_killed_thread, 'TODO')
  # timeout only on mswin, not mingw
  exclude(:test_thread_join_during_finalizers, 'Timeout')
end
