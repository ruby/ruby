These files are "known-good" compiler output, generated from a stable version of
Racc. Whenever Racc is refactored, or changes are made which should not affect the
compiler output, running "rake test" checks that the compiler output is exactly
the same as these files.

If a change is made which *should* change the compiler output, these files will
have to be regenerated from the source in test/assets, and the results committed.
