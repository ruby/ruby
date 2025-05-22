### Remarks

Run it with no argument. It will generate 12 files: 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, + and =.

```sh
ruby entry.rb
```

Concat and syntax highlight them.

```sh
cat 2 0 + 2 5 = | ruby -run -e colorize
cat 4 + 1 5 + 4 + 1 8 = | ruby -run -e colorize
```

I confirmed the following implementations/platforms:

* ruby 3.4.1 (2024-12-25 revision 48d4efcb85) +YJIT +MN +PRISM [arm64-darwin22]
* ruby 3.3.0 (2023-12-25 revision 5124f9ac75) +YJIT +MN [arm64-darwin22]

### Description

Did you know that Ruby syntax can perform additive operations on two-digit numbers without Ruby runtime? This entry demonstrates a syntax level computation of Ruby grammar.

`ruby entry.rb` will generate 12 files: 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, + and =.
These files constitute a calculator system that runs on Ruby parser.

To calculate `6 + 7`, concat `6`, `+`, `7` and `=`.

```sh
cat 6 + 7 =
```

The concatenated output is a Ruby script that does nothing. It is also an ASCII art of `█ + █ = ██` rotated 90 degrees.
Now, let's try syntax highlighting that code.

```sh
cat 6 + 7 = | ruby -run -e colorize
```

Wow! You can see the calculation result `6 + 7 = 13` as a colorized ASCII art!

This system can also add more than two numbers. All numbers should be one or two digits, and the answer should be less than 100.

```sh
cat 3 1 + 4 + 1 5 + 9 = | ruby -run -e colorize
cat 1 + 2 + 4 + 8 + 1 6 + 3 2 = | ruby -run -e colorize
cat 0 + 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 1 0 = | ruby -run -e colorize
```

If the syntax highlighting is hard to see, use this command to change the terminal color.

```sh
printf "\e]11;#000000\a\e]10;#333333\a\e]4;1;#ffaaaa\a"
```

### Internals

To perform calculation, you need a storage and a control flow statement.
Local variable existence can be used as a storage.
Ruby syntax provides conditional local variable definition and local variable reset with state carry over which can be used as a control flow statement.

#### Conditional Local Variable Definition

Ruby syntax can define new local variables conditionally.

```ruby
# Defines x and y if a is defined
a /x = y = 1./
# Defines x and y if a is not defined
a /1#/; x = y = 1
# Defines x or y depend on the existence of local variable a
a /(x=1);'/;(y=1);?'
```

#### Local Variables Reset

Local variables can be cleared by creating a new `def` scope.

```ruby
x = y = z = 1
def f
# x, y, z are cleared
```

#### State Carry Over

Some state should be carried over to the next `def` scope. There are two tricks to do it.

```ruby
a /%+/i; b /%-/i; def f(x)# +; def f(y) # -; def f(z)
```

```ruby
a %(<<A); b %(<<B); def f
x=<<C
A
y=<<C
B
z=<<C
C
```

In both examples above, local variable defined in the new scope will be:

```ruby
x # if both a and b are not defined
y # if a is defined
z # if b is defined
```

Combining these two tricks, Ruby syntax can carry over two states to the next `def` scope. In this system, two states represents upper digit and lower digit.

### File Structure

```ruby
# File 0, 1, 2, 3, 4, 5, 6, 7, 8, 9
(code) &&
```

```ruby
# File +
(code) && def f(arg)=
```

```ruby
# File =
(code) if exit
```

```ruby
# cat 1 2 + 3 + 4 5 =
(one) &&
(two) &&
(plus) && def f(arg)=
(three) &&
(plus) && def f(arg)=
(four) &&
(five) &&
(equal) if exit
```

### Limitation

Number to be added must be one or two digits.
Answer of the addition must be less than 100.
