str1 = "あ" * 1024 + "い" # not single byte optimizable
str2 = "い"
100_000.times { str1.index(str2) }
