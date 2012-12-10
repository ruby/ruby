if compiled?('dl') and !complied?('fiddle') and $mswin||$bccwin||$mingw||$cygwin
  create_makefile('win32')
end
