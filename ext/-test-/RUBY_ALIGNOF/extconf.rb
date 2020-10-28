# frozen_string_literal: false
$objs = %W"c.#$OBJEXT"

$objs << "cpp.#$OBJEXT" if MakeMakefile['C++'].have_devel?

create_makefile("-test-/RUBY_ALIGNOF")
