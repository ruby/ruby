if ENV['APPVEYOR'] == 'True' && RUBY_PLATFORM.match?(/mswin/)
  exclude(/\Atest_/, 'test_win32ole.rb sometimes causes worker crash')
  # separately tested on appveyor.yml.
end

# https://ci.appveyor.com/project/ruby/ruby/build/9811/job/ra5uxf2cg6v7ohag
#
# running file: C:/projects/ruby/test/win32ole/test_win32ole.rb
#
# Some worker was crashed. It seems ruby interpreter's bug
# or, a bug of test/unit/parallel.rb. try again without -j
# option.
# NMAKE : fatal error U1077: '.\ruby.exe' : return code '0x1'
