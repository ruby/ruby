# frozen_string_literal: false
if $mswin
  $CXXFLAGS << " -EHsc"
  create_makefile("-test-/win32/cxx_catch")
end
