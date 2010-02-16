#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_finish 1, %q{
  open("tst-remove-load.rb", "w") {|f|
    f << <<'End'
module Kernel
  remove_method :load
end
raise
End
  }
  load "tst-remove-load.rb"
}, '[ruby-dev:40234] [ruby-core:27959]'
