call-seq:
  pos -> byte_position

Returns the integer [byte position][2],
which may be different from the [character position][7]:

```rb
scanner = StringScanner.new(HIRAGANA_TEXT)
scanner.string  # => "こんにちは"
scanner.pos     # => 0
scanner.getch   # => "こ" # 3-byte character.
scanner.charpos # => 1
scanner.pos     # => 3
```
