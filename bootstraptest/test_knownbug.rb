#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_normal_exit %q{
  null = File.exist?("/dev/null") ? "/dev/null" : "NUL" # maybe DOSISH
  File.read(null).clone
}, '[ruby-dev:32819] reported by Kazuhiro NISHIYAMA'

assert_normal_exit %q{
  class Foo
     def self.add_method
       class_eval("def some-bad-name; puts 'hello' unless @some_variable.some_function(''); end")
     end
  end
  Foo.add_method
}, '[ruby-core:14556] reported by Frederick Cheung'

