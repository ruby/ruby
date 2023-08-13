# frozen_string_literal: false
exclude(/_stack_size$/, 'often too expensive')
if /freebsd13/ =~ RUBY_PLATFORM
  # http://rubyci.s3.amazonaws.com/freebsd13/ruby-master/log/20220216T143001Z.fail.html.gz
  #
  #   1) Error:
  # TestThread#test_signal_at_join:
  # Timeout::Error: execution of assert_separately expired timeout (120 sec)
  # pid 30743 killed by SIGABRT (signal 6) (core dumped)
  # |
  #
  #     /usr/home/chkbuild/chkbuild/tmp/build/20220216T143001Z/ruby/test/ruby/test_thread.rb:1390:in `test_signal_at_join'
  exclude(:test_signal_at_join, 'gets stuck somewhere')
end
