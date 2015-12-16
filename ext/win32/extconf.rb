# frozen_string_literal: false
if compiled?('fiddle') and $mswin||$mingw||$cygwin
  create_makefile('win32')
end
