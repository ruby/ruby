#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_normal_exit %q{
  STDERR.reopen(STDOUT)
  class Foo
     def self.add_method
       class_eval("def some-bad-name; puts 'hello' unless @some_variable.some_function(''); end")
     end
  end
  Foo.add_method
}, '[ruby-core:14556] reported by Frederick Cheung'

