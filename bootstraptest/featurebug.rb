assert_equal 'ok', %q{
  1.times{
    eval("break")
  }
  :ok
}, '[ruby-dev:32525]'
