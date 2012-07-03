#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

[['[ruby-dev:45656]', %q{
  class Bug6460
    include Enumerable
    def each
      begin
        yield :foo
      ensure
        1.times { Proc.new }
      end
    end
  end
  e = Bug6460.new
}]].each do |bug, src|
  assert_equal "foo", src + %q{e.detect {true}}, bug
  assert_equal "true", src + %q{e.any? {true}}, bug
  assert_equal "false", src + %q{e.all? {false}}, bug
  assert_equal "true", src + %q{e.include?(:foo)}, bug
end
