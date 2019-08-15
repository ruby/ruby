# https://travis-ci.org/ruby/ruby/jobs/454707326
# maybe this test's timeout should be re-arranged for Travis osx
exclude(:test_nested_timeout_outer, 'This test randomly fails on Travis osx')
