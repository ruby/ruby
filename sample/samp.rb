# 全角文字を含むスクリプト
# 使い方: samp.rb file..

単語 = 0
while gets()
  printf("%3d: %s", $., $_)
  while sub(/\w+/, '')
    if $& != "";
      単語 += 1
    end
  end
  if ($. >= 10); break; end
end
printf("line: %d\n", $.)
printf("word: %d\n", 単語)
