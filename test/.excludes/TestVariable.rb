if RUBY_DESCRIPTION.include?("+PRISM")
  exclude(:test_local_variables_encoding, "[Bug #20992]")
end
