#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_not_match /method_missing/, %q{
  STDERR.reopen(STDOUT)
  variable_or_mehtod_not_exist
}

assert_equal 'ok', %q{
  begin
    Regexp.union(
      "a",
      Regexp.new("\x80".force_encoding("euc-jp")),
      Regexp.new("\x80".force_encoding("utf-8")))
    :ng
  rescue ArgumentError
    :ok
  end
}

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

