#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_normal_exit %q{
  STDERR.reopen(STDOUT)
  require 'yaml'
  YAML.load("2000-01-01 00:00:00.#{"0"*1000} +00:00\n")
}, '[ruby-core:13735]'

assert_equal 'ok', %q{
  class C
    def each
      yield [1,2]
      yield 1,2
    end
  end
  vs1 = []
  C.new.each {|*v| vs1 << v }
  vs2 = []               
  C.new.to_enum.each {|*v| vs2 << v }
  vs1 == vs2 ? :ok : :ng
}, '[ruby-dev:32329]'

assert_equal '..f00000000', %q{
  sprintf("%x", -2**32)
}, '[ruby-dev:32351]'

assert_equal "..101111111111111111111111111111111", %q{
  sprintf("%b", -2147483649)
}, '[ruby-dev:32365]'
