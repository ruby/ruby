
# Mutex

class Mutex
  class Mutex
    def synchronize
      self.lock
      yield
    ensure
      self.unlock
    end
  end
end

