def require_relative(relative_feature)
  /:/ =~ caller.first
  absolute_feature = File.expand_path(File.join(File.dirname($`), relative_feature))
  require absolute_feature
end

