if nul = $:.find_index {|path| /\A(?:\.\/)*-\z/ =~ path}
  $:[nul..-1] = ["."]
end
