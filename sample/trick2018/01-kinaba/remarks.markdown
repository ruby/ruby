### Remarks

Just run it with no argument:

    ruby entry.rb

(Anyway it is just a no-op program. The above command only verifies
that entry.rb is a valid Ruby program.)

I confirmed the following implementations/platforms:

* ruby 2.5.0p0 (2017-12-25 revision 61468) [x64-mingw32]

### Description

First, look at

https://docs.ruby-lang.org/ja/latest/doc/spec=2flexical.html#reserved

and then, look at entry.rb.

The source code of entry.rb consists only of reserved words of Ruby,
and all the reserved words are used in the code, in a way that the code
forms a valid Ruby program. No compile error, no warning, or no runtime error.


### Internals

Difficult (and interesting) points of the theme are:

* Since many of the reserved words define program structures, we cannot
  use them independently. For instance, `retry` must be inside `rescue`,
  or `break`/`next`/`redo` must be inside a looping construct.
  Or, jump-out statements cannot occur at a position that requires a
  value; `if return then true end` is a "void value expression" syntax error.
* Inserting newlines for each 6 word (to match with the spec html) is also
  an interseting challenge, since Ruby is sensitive to newlines.

Tricks used in the code are:

* def/alias/undef can take even reserved words as parameters.
  That is, `def class ... end` defines a method named `class`.
  The feature is crucial since otherwise `BEGIN` etc inevitably
  introduces non-reserved tokens (like `{}`).
* `defined?` can take some reserved words too (which I didn't know
  until trying to write this program.)
* "void value expression" can be avoided by using `or` or `and`.
  `if begin return end then true end` is a syntax error, but
  `if begin false or return end then true end` is not.


### Limitation

Sad to say that it's not a "perfect pangram".
It uses 'alias' and 'undef' twice, and 'end' 4 times.
