#! /usr/local/bin/ruby

path = ENV['PATH'].split(File::PATH_SEPARATOR)

for dir in path
  if File.directory?(dir)
    for f in d = Dir.open(dir)
      fpath = dir+"/"+f  
      if File.file?(fpath) && (File.stat(fpath).mode & 022) != 0
	printf("file %s is writable from other users\n", fpath)
      end
    end
    d.close
  end
end
