#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_equal 'ok', %q{
  open("tmp", "w") {|f| f.write "a\u00FFb" }
  s = open("tmp", "r:iso-8859-1:utf-8") {|f|
    f.gets("\xFF".force_encoding("iso-8859-1"))
  }
  s == "a\xFF" ? :ok : :ng
}, '[ruby-core:14288]'
