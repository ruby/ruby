# directory access
# list all files but .*/*~/*.o
dirp = Dir.open(".")
for f in dirp
  $_ = f
  if (~/^\./ || ~/~$/ || ~/\.o/)
    print f, "\n"
  end
end
dirp.close
