# Observable Mixin
# 
# Observers must respond to update

module Observable
  def add_observer(observer)
    @observer_peers = [] unless @observer_peers
    unless defined? observer.update
      raise NameError, "observer needs to respond to `update'" 
    end
    @observer_peers.push observer
  end
  def delete_observer(observer)
    @observer_peers.delete observer if @observer_peers
  end
  def delete_observers
    @observer_peers.clear if @observer_peers
  end
  def count_observers
    if @observer_peers
      @observer_peers.size
    else
      0
    end
  end
  def changed(state=TRUE)
    @observer_state = state
  end
  def changed?
    @observer_state
  end
  def notify_observers(*arg)
    if @observer_state
      if @observer_peers
	for i in @observer_peers
	  i.update(*arg)
	end
      end
      @observer_state = FALSE
    end
  end
end
