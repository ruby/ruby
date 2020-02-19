# NEWS for Ruby 2.8.0 (tentative; to be 3.0.0)

This document is a list of user visible feature changes
since the **2.7.0** release, except for bug fixes.

Note that each entry is kept so brief that no reason behind or reference
information is supplied with.  For a full list of changes with all
sufficient information, see the ChangeLog file or Redmine
(e.g. `https://bugs.ruby-lang.org/issues/$FEATURE_OR_BUG_NUMBER`).

## Language changes

* $SAFE is now a normal global variable with no special behavior.
  [[Feature #16131]]

* yield in singleton class definitions in methods is now a SyntaxError.
  [[Feature #15575]]

## Command line options

## Core classes updates (outstanding ones only)

* Dir

    * Modified method

        * Dir.glob and Dir.[] now sort the results by default, and
          accept `sort:` keyword option.  [[Feature #8709]]

* Hash

    * Modified method

        * Hash#transform_keys now accepts a hash that maps keys to new
          keys.  [[Feature #16274]]

* Symbol

    * Modified method

        * Symbol#to_proc now returns a lambda Proc.
          [[Feature #16260]]

## Stdlib updates (outstanding ones only)

* Net::HTTP

    * New method

        * Add Net::HTTP#verify_hostname= and Net::HTTP#verify_hostname
          to skip hostname verification.  [[Feature #16555]]

## Compatibility issues (excluding feature bug fixes)

* Regexp literals are frozen [[Feature #8948]] [[Feature #16377]]

    ```ruby
    /foo/.frozen? #=> true
    ```

* Bundled gems

    * net-telnet and xmlrpc have been removed from the bundled gems.
      If you are interested in maintaining them, please comment on
      your plan to https://github.com/ruby/xmlrpc
      or https://github.com/ruby/net-telnet.

## Stdlib compatibility issues (excluding feature bug fixes)

## C API updates

## Implementation improvements

## Miscellaneous changes


[Feature #8709]:  https://bugs.ruby-lang.org/issues/8709
[Feature #8948]:  https://bugs.ruby-lang.org/issues/8948
[Feature #15575]: https://bugs.ruby-lang.org/issues/15575
[Feature #16131]: https://bugs.ruby-lang.org/issues/16131
[Feature #16260]: https://bugs.ruby-lang.org/issues/16260
[Feature #16274]: https://bugs.ruby-lang.org/issues/16274
[Feature #16377]: https://bugs.ruby-lang.org/issues/16377
[Feature #16555]: https://bugs.ruby-lang.org/issues/16555
