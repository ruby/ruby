class ProfileAction
  def initialize
    @describe_name = nil
    @describe_time = nil
    @describes = []
    @its = []
  end

  def register
    MSpec.register :enter, self
    MSpec.register :before,self
    MSpec.register :after, self
    MSpec.register :finish,self
  end

  def enter(describe)
    if @describe_time
      @describes << [@describe_name, now - @describe_time]
    end

    @describe_name = describe
    @describe_time = now
  end

  def before(state)
    @it_name = state.it
    @it_time = now
  end

  def after(state = nil)
    @its << [@describe_name, @it_name, now - @it_time]
  end

  def finish
    puts "\nProfiling info:"

    desc = @describes.sort { |a,b| b.last <=> a.last }
    desc.delete_if { |a| a.last <= 0.001 }
    show = desc[0, 100]

    puts "Top #{show.size} describes:"

    show.each do |des, time|
      printf "%3.3f - %s\n", time, des
    end

    its = @its.sort { |a,b| b.last <=> a.last }
    its.delete_if { |a| a.last <= 0.001 }
    show = its[0, 100]

    puts "\nTop #{show.size} its:"
    show.each do |des, it, time|
      printf "%3.3f - %s %s\n", time, des, it
    end
  end

  def now
    Time.now.to_f
  end
end
