# frozen_string_literal: false
$INCFLAGS << " -I$(topdir) -I$(top_srcdir)"
create_makefile("-test-/thread/fork_lock")
