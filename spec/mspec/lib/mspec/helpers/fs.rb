# Copies a file
def cp(source, dest)
  File.open(dest, "wb") do |d|
    File.open(source, "rb") do |s|
      while data = s.read(1024)
        d.write data
      end
    end
  end
end

# Creates each directory in path that does not exist.
def mkdir_p(path)
  parts = File.expand_path(path).split %r[/|\\]
  name = parts.shift
  parts.each do |part|
    name = File.join name, part

    if File.file? name
      raise ArgumentError, "path component of #{path} is a file"
    end

    unless File.directory? name
      begin
        Dir.mkdir name
      rescue Errno::EEXIST => e
        if File.directory? name
          # OK, another process/thread created the same directory
        else
          raise e
        end
      end
    end
  end
end

# Recursively removes all files and directories in +path+
# if +path+ is a directory. Removes the file if +path+ is
# a file.
def rm_r(*paths)
  paths.each do |path|
    path = File.expand_path path

    prefix = SPEC_TEMP_DIR
    unless path[0, prefix.size] == prefix
      raise ArgumentError, "#{path} is not prefixed by #{prefix}"
    end

    # File.symlink? needs to be checked first as
    # File.exist? returns false for dangling symlinks
    if File.symlink? path
      File.unlink path
    elsif File.directory? path
      Dir.entries(path).each { |x| rm_r "#{path}/#{x}" unless x =~ /^\.\.?$/ }
      Dir.rmdir path
    elsif File.exist? path
      File.delete path
    end
  end
end

# Creates a file +name+. Creates the directory for +name+
# if it does not exist.
def touch(name, mode="w")
  mkdir_p File.dirname(name)

  File.open(name, mode) do |f|
    yield f if block_given?
  end
end
