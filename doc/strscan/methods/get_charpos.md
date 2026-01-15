call-seq:
  charpos -> character_position

Returns the [character position][7] (initially zero),
which may be different from the [byte position][2]
given by method #pos:

```rb
scanner = StringScanner.new(HIRAGANA_TEXT)
scanner.string # => "こんにちは"
scanner.getch  # => "こ" # 3-byte character.
scanner.getch  # => "ん" # 3-byte character.
put_situation(scanner)
# Situation:
#   pos:       6
#   charpos:   2
#   rest:      "にちは"
#   rest_size: 9
```
