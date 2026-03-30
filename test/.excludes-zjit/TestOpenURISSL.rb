if RUBY_PLATFORM =~ /linux/
  exclude(/test_/, 'randomly fails with SystemStackError (Shopify/ruby#964)')
end
