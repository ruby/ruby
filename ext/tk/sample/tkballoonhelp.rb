#
# tkballoonhelp.rb : simple balloon help widget
#                       by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
# Add a balloon help to a widget. 
# This widget has only poor featureas. If you need more useful features, 
# please try to use the Tix extension of Tcl/Tk under Ruby/Tk.
# 
# The interval time to display a balloon help is defined 'interval' option
# (default is 1000ms). 
#
require 'tk'

class TkBalloonHelp<TkLabel
  def _balloon_binding(interval)
    @timer = TkAfter.new(interval, 1, proc{show})
    def @timer.interval(val)
      @sleep_time = val
    end
    @bindtag = TkBindTag.new
    @bindtag.bind('Enter',  proc{@timer.start})
    @bindtag.bind('Motion', proc{@timer.restart; erase})
    @bindtag.bind('Any-ButtonPress', proc{@timer.restart; erase})
    @bindtag.bind('Leave',  proc{@timer.stop; erase})
    tags = @parent.bindtags
    idx = tags.index(@parent)
    tags[idx,0] = @bindtag
    @parent.bindtags(tags)
  end
  private :_balloon_binding

  def initialize(parent=nil, keys={})
    @parent = parent

    @frame = TkToplevel.new(@parent)
    @frame.withdraw
    @frame.overrideredirect(true)
    @frame.transient(TkWinfo.toplevel(@parent))
    @epath = @frame.path

    keys = {} unless keys

    @interval = keys.delete('interval'){1000}
    _balloon_binding(@interval)

    @label = TkLabel.new(@frame, 'background'=>'bisque').pack
    @label.configure(_symbolkey2str(keys)) unless keys.empty?
    @path = @label
  end

  def epath
    @epath
  end

  def interval(val)
    if val
      @timer.interval(val)
    else
      @interval
    end
  end

  def show
    x = TkWinfo.pointerx(@parent)
    y = TkWinfo.pointery(@parent)
    @frame.geometry("+#{x+1}+#{y+1}")
    @frame.deiconify
    @frame.raise

    @org_cursor = @parent['cursor']
    @parent.cursor('crosshair') 
  end

  def erase
    @parent.cursor(@org_cursor) 
    @frame.withdraw
  end

  def destroy
    @frame.destroy
  end
end

################################################
# test
################################################
if __FILE__ == $0
  TkButton.new('text'=>'This button has a balloon help') {|b|
    pack('fill'=>'x')
    TkBalloonHelp.new(b, 'text'=>' Message ')
  }
  TkButton.new('text'=>'This button has another balloon help') {|b|
    pack('fill'=>'x')
    TkBalloonHelp.new(b, 'text'=>'configured message', 
                      'interval'=>200, 'font'=>'courier', 
                      'background'=>'gray', 'foreground'=>'red')
  }
  Tk.mainloop
end
