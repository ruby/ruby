MAIN = self

module X
  MAIN.send(:using, Module.new)
end
