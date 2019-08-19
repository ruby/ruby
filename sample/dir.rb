# directory access
# list all files but .*/*~/*.o
dirp = Dir.open(".")
dirp.each do |f|
  case f
  when /\A\./, /~\z/, /\.o/
    # do not print
  else
    print f, "\n"
  end
end
dirp.close
