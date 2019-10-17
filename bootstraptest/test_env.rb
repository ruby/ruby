assert_equal "true", %q{
  ENV["ENVTEST"] = "\u{e9 3042 d76c}"
  env = ENV["ENVTEST"]
  env.valid_encoding?
}

# different encoding is used for PATH
assert_equal "true", %q{
  ENV["PATH"] = "\u{e9 3042 d76c}"
  env = ENV["PATH"]
  env.valid_encoding?
}
