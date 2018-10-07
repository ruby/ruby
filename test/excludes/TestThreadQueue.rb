if ENV['APPVEYOR'] == 'True' && RUBY_PLATFORM.match?(/mswin/)
  exclude :test_queue_with_trap, 'too unstable on vs140'
  # separately tested on appveyor.yml.
end

# https://ci.appveyor.com/project/ruby/ruby/build/9795/job/l9t4w9ks7arsldb1
#   1) Error:
# TestThreadQueue#test_queue_with_trap:
# Timeout::Error: execution of assert_in_out_err expired timeout (30.0 sec)
# pid 22988 exit 0
# |
#     C:/projects/ruby/test/ruby/test_thread_queue.rb:553:in `test_queue_with_trap'
