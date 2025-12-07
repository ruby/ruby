assert_equal %q{ok}, %q{
  :ok # This is a comment
}

assert_equal %q{ok}, %q{
  (| This is a comment also |) :ok
}
