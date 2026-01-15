### Summary

This is a rot13 filter.  Given an input text, it will **rotate** the text by **pi/13** radians.  Two modes of operation are available, selected based on number of command line arguments.

Rotate clockwise:

    ruby entry.rb < input.txt

Rotate counterclockwise:

    ruby entry.rb input.txt
    ruby entry.rb - < input.txt

### Details

This program interprets input as an ASCII art with each character representing individual square pixels, and produces a rotated image to stdout.  All non-whitespace characters are preserved in output, only the positions of those characters are adjusted.  While all the characters are preserved, the words and sentences will not be as readable in their newly rotated form.  This makes the program suitable for obfuscating text.

    ruby entry.rb original.txt > rotated.txt
    ruby entry.rb < rotated.txt > unrotated.txt

But note that while `unrotated.txt` is often the same as `original.txt`, there is no hard guarantee due to integer rounding intricacies.  Whether the original text can be recovered depends a lot on its shape, be sure to check that the output is reversible if you are using this rot13 filter to post spoilers and such.

Reversibility does hold for `entry.rb`:

    ruby entry.rb entry.rb | ruby entry.rb | diff entry.rb -
    ruby entry.rb < entry.rb | ruby entry.rb - | diff entry.rb -

Also, there is a bit of text embedded in the rotated version:

    ruby entry.rb entry.rb | ruby

But this text is encrypted!  No problem, just rotate `entry.rb` the other way for the decryption tool:

    ruby entry.rb < entry.rb > caesar_cipher_shift_13.rb
    ruby entry.rb entry.rb | ruby | ruby caesar_cipher_shift_13.rb

If current shell is `bash` or `zsh`, this can be done all in one line:

    ruby entry.rb entry.rb | ruby | ruby <(ruby entry.rb < entry.rb)

### Miscellaneous features

To rotate to a different angle, edit the first line of `entry.rb`.  Angles between -pi/2 and pi/2 will work best, anything outside that range produces more distortion than rotation, although the output might still be reversible.

Setting angle to zero makes this program a filter that expands tabs, trim whitespaces, and canonicalize end-of-line sequences.

This program preserves non-ASCII characters since input is tokenized with `each_grapheme_cluster`, although all characters that's not an ASCII space/tab/newline are given the same treatment.  For example, the full-width space character (U+3000) will be transformed as if it's a half-width non-whitespace ASCII character.

If input contains only whitespace characters, output will be empty.

The layout is meant to resemble a daruma doll.  There was still ~119 bytes of space left after fitting in 3 ruby programs, so I embedded a brainfuck program as well.

    ruby bf.rb entry.rb

A `sample_input.txt` has been included for testing.  After rotating this file 26 times either clockwise or counterclockwise, you should get back the original `sample_input.txt`.

    ruby entry.rb < sample_input.txt | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | ruby entry.rb | diff sample_input.txt -
    ruby entry.rb sample_input.txt | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | ruby entry.rb - | diff sample_input.txt -

Additional development notes can be found in `spoiler_rot13.txt` (rotate clockwise to decode).

    ruby entry.rb < spoiler_rot13.txt

### Compatibility

Program has been verified to work under these environments:

   * ruby 3.2.2 on cygwin.
   * ruby 2.5.1p57 on linux.
   * ruby 2.7.4p191 on linux.
   * ruby 2.7.1p83 on jslinux.
