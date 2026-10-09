# frozen_string_literal: false
if $mswin || $mingw
  $CXXFLAGS << " -EHsc" if $mswin
  create_makefile("-test-/win32/cxx_catch")
end
