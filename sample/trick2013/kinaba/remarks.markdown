### Remarks

Just run it with no argument:

    ruby entry.rb

I confirmed the following implementations/platforms:

* ruby 2.0.0p0 (2013-02-24) [i386-mswin32\_100]

### Description

The program prints each ASCII character from 0x20 ' ' to 0x7e '~' exactly once.

The program contains each ASCII character from 0x20 ' ' to 0x7e '~' exactly once.

### Internals

The algorithm is the obvious loop "32.upto(126){|x| putc x}".

It is not so hard to transform it to use each character *at most once*. The only slight difficulty comes from the constraint that we cannot "declare and then use" variables, because then the code will contain the variable name twice. This restriction is worked around by the $. global variable, the best friend of Ruby golfers.

The relatively interesting part is to use all the characters *at least once*. Of course, this is easily accomplished by putting everything into a comment (i.e., #unused...) or to a string literal (%(unused...), note that normal string literals are forbidden since they use quotation marks twice). Hey, but that's not fun at all! I tried to minimize the escapeway.

* "@THEqQUICKbBROWNfFXjJMPSvVLAZYDGgkyz". Trash box of unused alphabet. I wish I could have used "gkyz" somewhere else.

* "%r{\"}mosx". Regex literal, with %-syntax. I don't even know what each m,o,s,x means...

* "?'" Symbol literal. The quote characters (' " \`) are the first obstacle to this trial because they have to be used in pair usually. These are escaped as \" and ?' and :\`.

* "4>6" "3\_0-~$.+=9/2^5" "18\*7". I had to consume many arithmetic operators +-\*/^~<>, but I only have ten literals 0 to 9 and $. as operands. Besides I have to express the print loop. This is an interesting puzzle.

* "(putc ...;)<18*7". Trail semicolon doesn't change the value of the expression.

### Limitation

n/a.
