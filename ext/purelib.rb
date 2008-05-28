nul = nil
$:.each_with_index {|path, index|
  if /\A(?:\.\/)*-\z/ =~ path
    nul = index
    break
  end
}
if nul
  $:[nul..-1] = ["."]
end
