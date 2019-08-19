[![Build Status](https://travis-ci.org/ruby/ruby.svg?branch=trunk)](https://travis-ci.org/ruby/ruby)
[![Build status](https://ci.appveyor.com/api/projects/status/0sy8rrxut4o0k960/branch/trunk?svg=true)](https://ci.appveyor.com/project/ruby/ruby/branch/trunk)
[![wercker status](https://app.wercker.com/status/e5e7e1704f62b76525022aa424aef6ef/s/trunk "wercker status")](https://app.wercker.com/project/byKey/e5e7e1704f62b76525022aa424aef6ef)

# What's Ruby

Ruby is the interpreted scripting language for quick and easy object-oriented
programming. It has many features to process text files and to do system
management tasks (as in Perl). It is simple, straight-forward, and
extensible.

## Features of Ruby

*   Simple Syntax
*   **Normal** Object-oriented Features (e.g. class, method calls)
*   **Advanced** Object-oriented Features (e.g. mix-in, singleton-method)
*   Operator Overloading
*   Exception Handling
*   Iterators and Closures
*   Garbage Collection
*   Dynamic Loading of Object Files (on some architectures)
*   Highly Portable (works on many Unix-like/POSIX compatible platforms as
    well as Windows, macOS, Haiku, etc.) cf.
    https://github.com/ruby/ruby/blob/trunk/doc/contributing.rdoc#platform-maintainers


## How to get Ruby

For a complete list of ways to install Ruby, including using third-party tools
like rvm, see:

https://www.ruby-lang.org/en/downloads/

The trunk of the Ruby source tree can be checked out with the following
command:

    $ svn co https://svn.ruby-lang.org/repos/ruby/trunk/ ruby

Or if you are using git then use the following command:

    $ git clone https://github.com/ruby/ruby.git

There are some other branches under development. Try the following command
to see the list of branches:

    $ svn ls https://svn.ruby-lang.org/repos/ruby/branches/

Or if you are using git then use the following command:

    $ git ls-remote https://github.com/ruby/ruby.git

## Ruby home page

The URL of the Ruby home page is:

https://www.ruby-lang.org/

## Mailing list

There is a mailing list to talk about Ruby. To subscribe to this list, please
send the following phrase:

    subscribe

in the mail body (not subject) to the address
<ruby-talk-request@ruby-lang.org>.

## How to compile and install

This is what you need to do to compile and install Ruby:

1.  If you want to use Microsoft Visual C++ to compile Ruby, read
    [win32/README.win32](win32/README.win32) instead of this document.

2.  If `./configure` does not exist or is older than `configure.ac`, run
    `autoconf` to (re)generate configure.

3.  Run `./configure`, which will generate `config.h` and `Makefile`.

    Some C compiler flags may be added by default depending on your
    environment. Specify `optflags=..` and `warnflags=..` as necessary to
    override them.

4.  Edit `defines.h` if you need. Usually this step will not be needed.

5.  Remove comment mark(`#`) before the module names from `ext/Setup` (or add
    module names if not present), if you want to link modules statically.

    If you don't want to compile non static extension modules (probably on
    architectures which do not allow dynamic loading), remove comment mark
    from the line "`#option nodynamic`" in `ext/Setup`.

    Usually this step will not be needed.

6.  Run `make`.

    * On Mac, set RUBY\_CODESIGN environment variable with a signing identity.
      It uses the identity to sign `ruby` binary. See also codesign(1).

7.  Optionally, run '`make check`' to check whether the compiled Ruby
    interpreter works well. If you see the message "`check succeeded`", your
    Ruby works as it should (hopefully).

8.  Optionally, run `make update-gems` and `make extract-gems`.

    If you want to install bundled gems, run `make update-gems` and
    `make extract-gems` before running `make install`.

9.  Run '`make install`'.

    This command will create the following directories and install files into
    them.

    *   `${DESTDIR}${prefix}/bin`
    *   `${DESTDIR}${prefix}/include/ruby-${MAJOR}.${MINOR}.${TEENY}`
    *   `${DESTDIR}${prefix}/include/ruby-${MAJOR}.${MINOR}.${TEENY}/${PLATFORM}`
    *   `${DESTDIR}${prefix}/lib`
    *   `${DESTDIR}${prefix}/lib/ruby`
    *   `${DESTDIR}${prefix}/lib/ruby/${MAJOR}.${MINOR}.${TEENY}`
    *   `${DESTDIR}${prefix}/lib/ruby/${MAJOR}.${MINOR}.${TEENY}/${PLATFORM}`
    *   `${DESTDIR}${prefix}/lib/ruby/site_ruby`
    *   `${DESTDIR}${prefix}/lib/ruby/site_ruby/${MAJOR}.${MINOR}.${TEENY}`
    *   `${DESTDIR}${prefix}/lib/ruby/site_ruby/${MAJOR}.${MINOR}.${TEENY}/${PLATFORM}`
    *   `${DESTDIR}${prefix}/lib/ruby/vendor_ruby`
    *   `${DESTDIR}${prefix}/lib/ruby/vendor_ruby/${MAJOR}.${MINOR}.${TEENY}`
    *   `${DESTDIR}${prefix}/lib/ruby/vendor_ruby/${MAJOR}.${MINOR}.${TEENY}/${PLATFORM}`
    *   `${DESTDIR}${prefix}/lib/ruby/gems/${MAJOR}.${MINOR}.${TEENY}`
    *   `${DESTDIR}${prefix}/share/man/man1`
    *   `${DESTDIR}${prefix}/share/ri/${MAJOR}.${MINOR}.${TEENY}/system`


    If Ruby's API version is '*x.y.z*', the `${MAJOR}` is '*x*', the
    `${MINOR}` is '*y*', and the `${TEENY}` is '*z*'.

    **NOTE**: teeny of the API version may be different from one of Ruby's
    program version

    You may have to be a super user to install Ruby.


If you fail to compile Ruby, please send the detailed error report with the
error log and machine/OS type, to help others.

Some extension libraries may not get compiled because of lack of necessary
external libraries and/or headers, then you will need to run '`make distclean-ext`'
to remove old configuration after installing them in such case.

## Copying

See the file [COPYING](COPYING).

## Feedback

Questions about the Ruby language can be asked on the Ruby-Talk mailing list
(https://www.ruby-lang.org/en/community/mailing-lists) or on websites like
(https://stackoverflow.com).

Bug reports should be filed at https://bugs.ruby-lang.org. Read [HowToReport] for more information.

[HowToReport]: https://bugs.ruby-lang.org/projects/ruby/wiki/HowToReport

## Contributing

See the file [CONTRIBUTING.md](CONTRIBUTING.md)


## The Author

Ruby was originally designed and developed by Yukihiro Matsumoto (Matz) in
1995.

<matz@ruby-lang.org>
