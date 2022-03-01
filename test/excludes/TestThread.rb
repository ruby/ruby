# frozen_string_literal: false
exclude(/_stack_size$/, 'often too expensive')
if /freebsd13/ =~ RUBY_PLATFORM
  exclude(:test_signal_at_join, 'gets stuck somewhere')
end
