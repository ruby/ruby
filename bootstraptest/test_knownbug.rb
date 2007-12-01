#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

$:.unshift File.join(File.dirname(__FILE__), "../.ext/#{RUBY_PLATFORM}")
assert_normal_exit %q{
  STDERR.reopen(STDOUT)
  require 'yaml'
  YAML.load("2000-01-01 00:00:00.#{"0"*1000} +00:00\n")
}, '[ruby-core:13735]'

assert_equal '..f00000000', %q{
  sprintf("%x", -2**32)
}, '[ruby-dev:32351]'

assert_equal "..101111111111111111111111111111111", %q{
  sprintf("%b", -2147483649)
}, '[ruby-dev:32365]'
