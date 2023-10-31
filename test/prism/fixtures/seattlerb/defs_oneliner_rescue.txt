def self.exec(cmd)
  system(cmd)
rescue
  nil
end


def self.exec(cmd)
  system(cmd) rescue nil
end


def self.exec(cmd) = system(cmd) rescue nil
