# frozen_string_literal: false
if $mingw or $mswin
  create_makefile("-test-/win32/exit_process")
end
