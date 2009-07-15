nul = nil
$:.each_with_index {|path, index|
  if /\A(?:\.\/)*-\z/ =~ path
    nul = index
    break
  end
}
if nul
  removed, $:[nul..-1] = $:[nul..-1], ["."]
  if defined?(Gem::QuickLoader)
    removed.each do |path|
      # replaces a fake rubygems by gem_prelude.rb with an alternative path
      index = $".index(File.join(path, 'rubygems.rb'))
      $"[index] = Gem::QuickLoader.path_to_full_rubygems_library if index
    end
  end
end
