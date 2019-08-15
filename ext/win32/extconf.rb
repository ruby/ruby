# frozen_string_literal: false
if $mswin||$mingw||$cygwin
  create_makefile('win32')
end
