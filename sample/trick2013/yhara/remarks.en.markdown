### Remarks

Just run it with no argument:

    ruby entry.rb

I confirmed the following implementations/platforms:

* ruby 2.0.0p0 (2013-02-24 revision 39474) [x86\_64-darwin12.2.1]

### Description

It prints JUST ANOTHER RUBY HACKER¡£

### Internals

This script uses characters in constants in Object class. It
intentionally raises some exceptions. The second 'U' comes from
RUBY\_COPYRIGHT, "Yukihiro Matsumoto".

### Limitation

This program does not work on JRuby because "return" does not raise an exception.
