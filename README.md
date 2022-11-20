[![Actions Status: MinGW](https://github.com/ruby/ruby/workflows/MinGW/badge.svg)](https://github.com/ruby/ruby/actions?query=workflow%3A"MinGW")
[![Actions Status: MJIT](https://github.com/ruby/ruby/workflows/MJIT/badge.svg)](https://github.com/ruby/ruby/actions?query=workflow%3A"MJIT")
[![Actions Status: Ubuntu](https://github.com/ruby/ruby/workflows/Ubuntu/badge.svg)](https://github.com/ruby/ruby/actions?query=workflow%3A"Ubuntu")
[![Actions Status: Windows](https://github.com/ruby/ruby/workflows/Windows/badge.svg)](https://github.com/ruby/ruby/actions?query=workflow%3A"Windows")
[![AppVeyor status](https://ci.appveyor.com/api/projects/status/0sy8rrxut4o0k960/branch/master?svg=true)](https://ci.appveyor.com/project/ruby/ruby/branch/master)
[![Travis Status](https://app.travis-ci.com/ruby/ruby.svg?branch=master)](https://app.travis-ci.com/ruby/ruby)
[![Cirrus Status](https://api.cirrus-ci.com/github/ruby/ruby.svg)](https://cirrus-ci.com/github/ruby/ruby/master)

# What is Ruby?

Ruby is an interpreted object-oriented programming language often
used for web development. It also offers many scripting features
to process plain text and serialized files, or manage system tasks.
It is simple, straightforward, and extensible.

## Features of Ruby

* Simple Syntax
* **Normal** Object-oriented Features (e.g. class, method calls)
* **Advanced** Object-oriented Features (e.g. mix-in, singleton-method)
* Operator Overloading
* Exception Handling
* Iterators and Closures
* Garbage Collection
* Dynamic Loading of Object Files (on some architectures)
* Highly Portable (works on many Unix-like/POSIX compatible platforms as
  well as Windows, macOS, etc.) cf.
  https://github.com/ruby/ruby/blob/master/doc/maintainers.rdoc#label-Platform+Maintainers

## How to get Ruby with Git

For a complete list of ways to install Ruby, including using third-party tools
like rvm, see:

https://www.ruby-lang.org/en/downloads/

The mirror of the Ruby source tree can be checked out with the following command:

    $ git clone https://github.com/ruby/ruby.git

There are some other branches under development. Try the following command
to see the list of branches:

    $ git ls-remote https://github.com/ruby/ruby.git

You may also want to use https://git.ruby-lang.org/ruby.git (actual master of Ruby source)
if you are a committer.

## How to build

see [Building Ruby](doc/contributing/building_ruby.md)

## Ruby home page

https://www.ruby-lang.org/

## Commands

The following commands are available on IRB.

* `cwws`
  * Show the current workspace.
* `cb`, `cws`, `chws`
  * Change the current workspace to an object.
* `bindings`, `workspaces`
  * Show workspaces.
* `edit`
  * Open a file with the editor command defined with `ENV["EDITOR"]`
    * `edit` - opens the file the current context belongs to (if applicable)
    * `edit foo.rb` - opens `foo.rb`
    * `edit Foo` - opens the location of `Foo`
    * `edit Foo.bar` - opens the location of `Foo.bar`
    * `edit Foo#bar` - opens the location of `Foo#bar`
* `pushb`, `pushws`
  * Push an object to the workspace stack.
* `popb`, `popws`
  * Pop a workspace from the workspace stack.
* `load`
  * Load a Ruby file.
* `require`
  * Require a Ruby file.
* `source`
  * Loads a given file in the current session.
* `irb`
  * Start a child IRB.
* `jobs`
  * List of current sessions.
* `fg`
  * Switches to the session of the given number.
* `kill`
  * Kills the session with the given number.
* `help`
  * Enter the mode to look up RI documents.
* `irb_info`
  * Show information about IRB.
* `ls`
  * Show methods, constants, and variables.
    `-g [query]` or `-G [query]` allows you to filter out the output.
* `measure`
  * `measure` enables the mode to measure processing time. `measure :off` disables it.
* `$`, `show_source`
  * Show the source code of a given method or constant.
* `@`, `whereami`
  * Show the source code around binding.irb again.
* `debug`
  * Start the debugger of debug.gem.

## Documentation

- [English](https://docs.ruby-lang.org/en/master/index.html)
- [Japanese](https://docs.ruby-lang.org/ja/master/index.html)

## Mailing list

There is a mailing list to discuss Ruby. To subscribe to this list, please
send the following phrase:

    subscribe

in the mail body (not subject) to the address [ruby-talk-request@ruby-lang.org].

[ruby-talk-request@ruby-lang.org]: mailto:ruby-talk-request@ruby-lang.org?subject=Join%20Ruby%20Mailing%20List&body=subscribe

## Copying

See the file [COPYING](rdoc-ref:COPYING).

## Feedback

Questions about the Ruby language can be asked on the [Ruby-Talk](https://www.ruby-lang.org/en/community/mailing-lists) mailing list
or on websites like https://stackoverflow.com.

Bugs should be reported at https://bugs.ruby-lang.org. Read ["Reporting Issues"](https://docs.ruby-lang.org/en/master/contributing/reporting_issues_md.html) for more information.

## Contributing

See ["Contributing to Ruby"](https://docs.ruby-lang.org/en/master/contributing_md.html), which includes setup and build instructions.

## The Author

Ruby was originally designed and developed by Yukihiro Matsumoto (Matz) in 1995.

<matz@ruby-lang.org>
