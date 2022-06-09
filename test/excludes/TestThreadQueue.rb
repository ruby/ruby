# frozen_string_literal: false
if /freebsd13/ =~ RUBY_PLATFORM
  # http://rubyci.s3.amazonaws.com/freebsd13/ruby-master/log/20220308T023001Z.fail.html.gz
  #
  #   1) Failure:
  # TestThreadQueue#test_thr_kill [/usr/home/chkbuild/chkbuild/tmp/build/20220308T023001Z/ruby/test/ruby/test_thread_queue.rb:175]:
  # only 169/250 done in 60 seconds.
  exclude(:test_thr_kill, 'gets stuck somewhere')
end
