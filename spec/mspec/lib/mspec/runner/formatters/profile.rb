require 'mspec/expectations/expectations'
require 'mspec/runner/formatters/dotted'

class ProfileFormatter < DottedFormatter
  def initialize(out=nil)
    super

    @describe_name = nil
    @describe_time = nil
    @describes = []
    @its = []
  end

  def register
    super
    MSpec.register :enter, self
  end

  # Callback for the MSpec :enter event. Prints the
  # +describe+ block string.
  def enter(describe)
    if @describe_time
      @describes << [@describe_name, Time.now.to_f - @describe_time]
    end

    @describe_name = describe
    @describe_time = Time.now.to_f
  end

  # Callback for the MSpec :before event. Prints the
  # +it+ block string.
  def before(state)
    super

    @it_name = state.it
    @it_time = Time.now.to_f
  end

  # Callback for the MSpec :after event. Prints a
  # newline to finish the description string output.
  def after(state)
    @its << [@describe_name, @it_name, Time.now.to_f - @it_time]
    super
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

    super
  end
end
