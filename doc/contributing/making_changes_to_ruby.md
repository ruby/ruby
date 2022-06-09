# Contributing a pull request

## Code style

Here are some general rules to follow when writing Ruby and C code for CRuby:

* Do not change code unrelated to your pull request (including style fixes)
* Indent 4 spaces for C without tabs (tabs are two levels of indentation, equivalent to 8 spaces)
* Indent 2 spaces for Ruby without tabs
* ANSI C style for function declarations
* Follow C99 Standard
* PascalStyle for class/module names
* UNDERSCORE_SEPARATED_UPPER_CASE for other constants
* Abbreviations should be all upper case

## Commit messages

Use the following style for commit messages:

* Use a succinct subject line
* Include reasoning behind the change in the commit message, focusing on why the change is being made
* Refer to  issue (such as `Fixes [Bug #1234]` or `Implements [Feature #3456]`), or discussion on the mailing list (such as [ruby-core:12345])

## CI

GitHub actions will run on each pull request.

There is [a CI that runs on master](https://rubyci.org/). It has broad coverage of different systems and architectures, such as Solaris SPARC and macOS.
