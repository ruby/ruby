if (compiled?('dl') or compiled?('fiddle')) and $mswin||$mingw||$cygwin
  create_makefile('win32')
end
