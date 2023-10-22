def exec(cmd)
  system(cmd)
rescue
  nil
end


def exec(cmd)
  system(cmd) rescue nil
end


def exec(cmd) = system(cmd) rescue nil
