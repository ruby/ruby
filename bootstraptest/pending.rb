assert_equal 'ok', %q{
  def m
    lambda{
      proc{
        return :ng1
      }
    }.call.call
    :ng2
  end

  begin
    m()
  rescue LocalJumpError
    :ok
  end
}

# This randomly fails on mswin.
assert_equal %q{[]}, %q{
  Thread.new{sleep}.backtrace
}
