# MJIT

Here are some tips that might be useful when you work on MJIT:

## Always run make install

Always run `make install` before running MJIT. It could easily cause a SEGV if you don't.
MJIT looks for the installed header for security reasons.

## --mjit-debug vs --mjit-debug=-ggdb3

`--mjit-debug=[flags]` allows you to specify arbitrary flags while keeping other compiler flags like `-O3`,
which is useful for profiling benchmarks.

`--mjit-debug` alone, on the other hand, disables `-O3` and adds debug flags.
If you're debugging MJIT, what you need to use is not `--mjit-debug=-ggdb3` but `--mjit-debug`.
