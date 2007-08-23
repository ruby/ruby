#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

# massign
assert_equal '[0,1,{2=>3}]', '[0,*[1],2=>3]', "[ruby-dev:31592]"


