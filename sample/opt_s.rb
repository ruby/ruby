#! ruby -s
if ($xyz)
  print("xyz = TRUE\n")
end
if ($zzz)
  print("zzz = ", $zzz, "\n")
end
print($ARGV.join(", "), "\n")
