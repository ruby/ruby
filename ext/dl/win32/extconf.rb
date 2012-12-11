if compiled?('dl') and !compiled?('fiddle') and $mswin||$bccwin||$mingw||$cygwin
  create_makefile('win32')
end
