module RDoc::RI::Paths
  begin
    require 'rubygems' unless defined?(Gem)

    # HACK dup'd from Gem.latest_partials and friends
    all_paths = []

    all_paths = Gem.path.map do |dir|
      Dir[File.join(dir, 'doc/*/ri')]
    end.flatten

    ri_paths = {}

    all_paths.each do |dir|
      if %r"/([^/]*)-((?:\d+\.)*\d+)/ri\z" =~ dir
        name, version = $1, $2
        ver = Gem::Version.new(version)
        if !ri_paths[name] or ver > ri_paths[name][0]
          ri_paths[name] = [ver, dir]
        end
      end
    end

    GEMDIRS = ri_paths.map { |k,v| v.last }.sort
  rescue LoadError
    GEMDIRS = []
  end
end
