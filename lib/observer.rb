# Observable Mixin
# 
# Observers must respond to update

module Observable
  def add_observer(observer)
    @observer_peers = [] unless defined? @observer_peers
    unless observer.respond_to? :update
      raise NameError, "observer needs to respond to `update'" 
    end
    @observer_peers.push observer
  end
  def delete_observer(observer)
    @observer_peers.delete observer if defined? @observer_peers
  end
  def delete_observers
    @observer_peers.clear if defined? @observer_peers
  end
  def count_observers
    if defined? @observer_peers
      @observer_peers.size
    else
      0
    end
  end
  def changed(state=true)
    @observer_state = state
  end
  def changed?
    if defined? @observer_state and @observer_state
      true
    else
      false
    end
  end
  def notify_observers(*arg)
    if defined? @observer_state and @observer_state
      if defined? @observer_peers
	for i in @observer_peers.dup
	  i.update(*arg)
	end
      end
      @observer_state = false
    end
  end
end
