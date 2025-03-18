call-seq:
  pos = n -> n
  pointer = n -> n

Sets the [byte position][2] and the [character position][11];
returns `n`.

Does not affect [match values][9].

For non-negative `n`, sets the position to `n`:

```rb
scanner = StringScanner.new(HIRAGANA_TEXT)
scanner.string  # => "こんにちは"
scanner.pos = 3 # => 3
scanner.rest    # => "んにちは"
scanner.charpos # => 1
```

For negative `n`, counts from the end of the [stored string][1]:

```rb
scanner.pos = -9 # => -9
scanner.pos      # => 6
scanner.rest     # => "にちは"
scanner.charpos  # => 2
```
