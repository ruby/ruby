# directory access
# list all files but .*/*~/*.o
dirp = Dir.open(".")
for f in dirp
  case f
  when /\A\./, /~\z/, /\.o\z/
    # do not print
  else
    print f, "\n"
  end
end
dirp.close
