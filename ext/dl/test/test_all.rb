require 'test_base'
require 'dl/import'

require 'test_dl2'
require 'test_func'
require 'test_import'

case RUBY_PLATFORM
when /cygwin/, /mingw32/, /mswin32/, /bccwin32/
  require 'test_win32'
end
