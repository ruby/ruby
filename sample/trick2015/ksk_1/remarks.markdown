### Remarks

The program is run with a positive integer as an argument, e.g.,
```shell
  ruby entry.rb 27
```
It has been confirmed to be run on
```
  ruby 1.9.3p385 (2013-02-06 revision 39114) [x86_64-darwin11.4.2]
  ruby 2.0.0p481 (2014-05-08 revision 45883) [universal.x86_64-darwin13]
  ruby 2.2.3p173 (2015-08-18 revision 51636) [x86_64-linux]
```


### Description

The program prints a Collatz sequence started with a given number,
that is, it repeatedly outputs numbers obtained by applying the
following Half-Or-Triple-Plus-One (HOTPO) process to the previous
number:

> If the number is even, divide it by two, otherwise, multiply it by three and add one.

until the number becomes 1.  Collatz conjectured that no matter from
the process starts it always eventually terminates.  This is still
an open problem, hence the program may not terminate for some
numbers.  It is known that there is no such exception below 2<sup>60</sup>.


### Internals

The source code does not contain either conditional branch or arithmetic operation.
The trick shall be revealed step by step.

First, the code is obfuscated by using `%`-notations,
`*`(String#join), `%`-formatting, restructuring, and so on.
Here is an equivalent readable program:
```ruby
n = ARGV[0].to_i
begin 
  # do nothing
end while begin
  puts n
  n = (/(.)...\1=/ =~ eval('[",,,,,"'+ '",'*n + '  ?=].join#"].join("3x+1?")'))
end
```
The line 
```ruby
  n = (/(.)...\1=/ =~ eval('[",,,,,"'+ '",'*n + '  ?=].join#"].join("3x+1?")'))
```
performs the HOTPO process.
The `eval` expression here returns a string as explained in detail later.
Since *regex*`=~`*str* returns index of first match of *regex* in *str*,
the regular expression `(.)...\1` must match the string
at index `n/2` if `n` is even and
at `3*n+1` if `n` is odd greater than 1.
The match must fail in the case of `n = 1` so that it returns `nil`.

The key of simulating the even-odd conditional branch on `n` in the
HOTPO process is an `n`-length sequence of the incomplete fragments
`",` where the double-quote `"` changes its role of opening/closing
string literals alternately.  If `n` is even, the string in the `eval`
expression is evaluated as
```ruby
  => '[",,,,,"'+ '",' + '",' + '",' + ... + '",' + '  ?=].join#...'
  => '[",,,,,"",",",...",  ?=].join#...'
```
where the last double-quote `"` is closing hence the code after `#` is
ignored as comments.  Note that `"ab""cd"` in Ruby is equivalent to
`"abcd"`.  Therefore the `eval` expression is evaluated into
```ruby
  ",,,,,...,="
```
where the number of commas is `5+n/2`.
As a result, the regular expression `(.)...\1=` matches `,,,,,=`
at the end of string, that is, at index `5+n/2-5 = n/2`.

If `n` is odd, the string in the `eval` expression is evaluated as
```ruby
  => '[",,,,,"'+ '",' + '",' + '",' + '",' + ... + '",' + '  ?=].join#"].join("3x+1?")'
  => '[",,,,,"",",",",...,",  ?=].join#"].join("3x+1?")'
```
where the last element in the array is `", ?=].join#"`.  Threfore the
`eval` expression is evaluated into 
```
  ",,,,,,3x+1?,3x+1?,...,3x+1?,  ?=].join#"
```
where the number of `,3x+1?` is `(n-1)/2`.  As a result, the regular
expression `(.)...\1=` matches `?,  ?=` at the almost end of string,
that is, at index `5+(n-1)/2*6-1 = 3n+1`, provided that the match
fails in the case of `n = 1` because the symbol `?` occurs only once
in the string.

One may notice that the string `3x+1` in the code could be other
four-character words.  I chose it because the Collatz conjecture is
also called the 3x+1 problem.


### Variant

The Collatz conjecture is equivalently stated as,

> no matter from the HOTPO process starts, it always eventually
  reaches the cycle of 4, 2, and 1

instead of termination of the process at 1.  This alternative
statement makes the program simpler because we do not have to care the
case of n = 1.  It can be obtained by replacing the regular expression
is simply `/=/` and removing a padding `",,,,,"`.  The program no
longer terminates, though.


### Limitation

The implementation requires to manipulate long strings even for some
small starting numbers.  For example, starting from 1,819, the number
will reach up to 1,276,936 which causes SystemStackError on Ruby 1.9.3.
The program works on Ruby 2.0.0 and 2.2.3, though.


