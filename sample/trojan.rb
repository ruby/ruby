#! /usr/local/bin/ruby
path = ENV['PATH'].split(/:/)

for dir in path
  if File.d(dir)
    for f in d = Dir.open(dir)
      fpath = dir+"/"+f  
      if File.f(fpath) && (File.stat(fpath).mode & 022) != 0
	printf("file %s is writable from other users\n", fpath)
      end
    end
    d.close
  end
end
