dirp = Dir.open(".")
dirp.rewind
for f in dirp
  if (~/^\./ || ~/~$/ || ~/\.o/)
  else
    print(f, "\n")
  end
end
dirp.close
