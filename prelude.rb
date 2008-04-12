
# Mutex

class Mutex
  def synchronize
    self.lock
    begin
      yield
    ensure
      self.unlock rescue nil
    end
  end
end

# Thread

class Thread
  MUTEX_FOR_THREAD_EXCLUSIVE = Mutex.new
  def self.exclusive
    MUTEX_FOR_THREAD_EXCLUSIVE.synchronize{
      yield
    }
  end
end

def require_relative(relative_feature)
  c = caller.first
  e = c.rindex(/:\d+:in /)
  file = $`
  if /\A\((.*)\)/ =~ file # eval, etc.
    raise LoadError, "require_relative is called in #{$1}"
  end
  absolute_feature = File.expand_path(File.join(File.dirname(file), relative_feature))
  require absolute_feature
end
