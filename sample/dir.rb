# directory access
# list all files but .*/*~/*.o
dirp = Dir.open(".")
dirp.rewind
for f in dirp
  if !(~/^\./ || ~/~$/ || ~/\.o/)
    print f, "\n"
  end
end
dirp.close
