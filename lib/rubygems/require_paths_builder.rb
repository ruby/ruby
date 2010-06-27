require 'rubygems'

module Gem::RequirePathsBuilder
  def write_require_paths_file_if_needed(spec = @spec, gem_home = @gem_home)
    require_paths = spec.require_paths
    return if require_paths.size == 1 and require_paths.first == "lib"
    file_name = "#{gem_home}/gems/#{@spec.full_name}/.require_paths".untaint
    File.open(file_name, "wb") do |file|
      file.puts require_paths
    end
  end
end

