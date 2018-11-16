# https://ci.appveyor.com/project/ruby/ruby/builds/20339189/job/ltdpffep976xtj85
# `test_push_over_ary_max': failed to allocate memory (NoMemoryError)
exclude(:test_push_over_ary_max, 'Sometimes AppVeyor has insufficient memory to run this test')
