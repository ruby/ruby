#! ruby -s
if ($xyz)
  print("xyz = TRUE\n")
end
if ($zzz)
  print("zzz = ", $zzz, "\n")
end
if ($ARGV.length > 0)
  print($ARGV.join(", "), "\n")
end
