#
# tk/winfo.rb : methods for winfo command
#
module TkWinfo
end

require 'tk'

module TkWinfo
  include Tk
  extend Tk

  TkCommandNames = ['winfo'.freeze].freeze

  def TkWinfo.atom(name, win=nil)
    if win
      number(tk_call_without_enc('winfo', 'atom', '-displayof', win, 
                                 _get_eval_enc_str(name)))
    else
      number(tk_call_without_enc('winfo', 'atom', _get_eval_enc_str(name)))
    end
  end
  def winfo_atom(name)
    TkWinfo.atom(name, self)
  end

  def TkWinfo.atomname(id, win=nil)
    if win
      _fromUTF8(tk_call_without_enc('winfo', 'atomname', 
                                    '-displayof', win, id))
    else
      _fromUTF8(tk_call_without_enc('winfo', 'atomname', id))
    end
  end
  def winfo_atomname(id)
    TkWinfo.atomname(id, self)
  end

  def TkWinfo.cells(window)
    number(tk_call_without_enc('winfo', 'cells', window))
  end
  def winfo_cells
    TkWinfo.cells self
  end

  def TkWinfo.children(window)
    list(tk_call_without_enc('winfo', 'children', window))
  end
  def winfo_children
    TkWinfo.children self
  end

  def TkWinfo.classname(window)
    tk_call_without_enc('winfo', 'class', window)
  end
  def winfo_classname
    TkWinfo.classname self
  end
  alias winfo_class winfo_classname

  def TkWinfo.colormapfull(window)
     bool(tk_call_without_enc('winfo', 'colormapfull', window))
  end
  def winfo_colormapfull
    TkWinfo.colormapfull self
  end

  def TkWinfo.containing(rootX, rootY, win=nil)
    if win
      window(tk_call_without_enc('winfo', 'containing', 
                                 '-displayof', win, rootX, rootY))
    else
      window(tk_call_without_enc('winfo', 'containing', rootX, rootY))
    end
  end
  def winfo_containing(x, y)
    TkWinfo.containing(x, y, self)
  end

  def TkWinfo.depth(window)
    number(tk_call_without_enc('winfo', 'depth', window))
  end
  def winfo_depth
    TkWinfo.depth self
  end

  def TkWinfo.exist?(window)
    bool(tk_call_without_enc('winfo', 'exists', window))
  end
  def winfo_exist?
    TkWinfo.exist? self
  end

  def TkWinfo.fpixels(window, dist)
    number(tk_call_without_enc('winfo', 'fpixels', window, dist))
  end
  def winfo_fpixels(dist)
    TkWinfo.fpixels self, dist
  end

  def TkWinfo.geometry(window)
    tk_call_without_enc('winfo', 'geometry', window)
  end
  def winfo_geometry
    TkWinfo.geometry self
  end

  def TkWinfo.height(window)
    number(tk_call_without_enc('winfo', 'height', window))
  end
  def winfo_height
    TkWinfo.height self
  end

  def TkWinfo.id(window)
    tk_call_without_enc('winfo', 'id', window)
  end
  def winfo_id
    TkWinfo.id self
  end

  def TkWinfo.interps(window=nil)
    if window
      tk_split_simplelist(tk_call_without_enc('winfo', 'interps',
                                              '-displayof', window))
    else
      tk_split_simplelist(tk_call_without_enc('winfo', 'interps'))
    end
  end
  def winfo_interps
    TkWinfo.interps self
  end

  def TkWinfo.mapped?(window)
    bool(tk_call_without_enc('winfo', 'ismapped', window))
  end
  def winfo_mapped?
    TkWinfo.mapped? self
  end

  def TkWinfo.manager(window)
    tk_call_without_enc('winfo', 'manager', window)
  end
  def winfo_manager
    TkWinfo.manager self
  end

  def TkWinfo.appname(window)
    tk_call('winfo', 'name', window)
  end
  def winfo_appname
    TkWinfo.appname self
  end

  def TkWinfo.parent(window)
    window(tk_call_without_enc('winfo', 'parent', window))
  end
  def winfo_parent
    TkWinfo.parent self
  end

  def TkWinfo.widget(id, win=nil)
    if win
      window(tk_call_without_enc('winfo', 'pathname', '-displayof', win, id))
    else
      window(tk_call_without_enc('winfo', 'pathname', id))
    end
  end
  def winfo_widget(id)
    TkWinfo.widget id, self
  end

  def TkWinfo.pixels(window, dist)
    number(tk_call_without_enc('winfo', 'pixels', window, dist))
  end
  def winfo_pixels(dist)
    TkWinfo.pixels self, dist
  end

  def TkWinfo.reqheight(window)
    number(tk_call_without_enc('winfo', 'reqheight', window))
  end
  def winfo_reqheight
    TkWinfo.reqheight self
  end

  def TkWinfo.reqwidth(window)
    number(tk_call_without_enc('winfo', 'reqwidth', window))
  end
  def winfo_reqwidth
    TkWinfo.reqwidth self
  end

  def TkWinfo.rgb(window, color)
    list(tk_call_without_enc('winfo', 'rgb', window, color))
  end
  def winfo_rgb(color)
    TkWinfo.rgb self, color
  end

  def TkWinfo.rootx(window)
    number(tk_call_without_enc('winfo', 'rootx', window))
  end
  def winfo_rootx
    TkWinfo.rootx self
  end

  def TkWinfo.rooty(window)
    number(tk_call_without_enc('winfo', 'rooty', window))
  end
  def winfo_rooty
    TkWinfo.rooty self
  end

  def TkWinfo.screen(window)
    tk_call('winfo', 'screen', window)
  end
  def winfo_screen
    TkWinfo.screen self
  end

  def TkWinfo.screencells(window)
    number(tk_call_without_enc('winfo', 'screencells', window))
  end
  def winfo_screencells
    TkWinfo.screencells self
  end

  def TkWinfo.screendepth(window)
    number(tk_call_without_enc('winfo', 'screendepth', window))
  end
  def winfo_screendepth
    TkWinfo.screendepth self
  end

  def TkWinfo.screenheight (window)
    number(tk_call_without_enc('winfo', 'screenheight', window))
  end
  def winfo_screenheight
    TkWinfo.screenheight self
  end

  def TkWinfo.screenmmheight(window)
    number(tk_call_without_enc('winfo', 'screenmmheight', window))
  end
  def winfo_screenmmheight
    TkWinfo.screenmmheight self
  end

  def TkWinfo.screenmmwidth(window)
    number(tk_call_without_enc('winfo', 'screenmmwidth', window))
  end
  def winfo_screenmmwidth
    TkWinfo.screenmmwidth self
  end

  def TkWinfo.screenvisual(window)
    tk_call_without_enc('winfo', 'screenvisual', window)
  end
  def winfo_screenvisual
    TkWinfo.screenvisual self
  end

  def TkWinfo.screenwidth(window)
    number(tk_call_without_enc('winfo', 'screenwidth', window))
  end
  def winfo_screenwidth
    TkWinfo.screenwidth self
  end

  def TkWinfo.server(window)
    tk_call('winfo', 'server', window)
  end
  def winfo_server
    TkWinfo.server self
  end

  def TkWinfo.toplevel(window)
    window(tk_call_without_enc('winfo', 'toplevel', window))
  end
  def winfo_toplevel
    TkWinfo.toplevel self
  end

  def TkWinfo.visual(window)
    tk_call_without_enc('winfo', 'visual', window)
  end
  def winfo_visual
    TkWinfo.visual self
  end

  def TkWinfo.visualid(window)
    tk_call_without_enc('winfo', 'visualid', window)
  end
  def winfo_visualid
    TkWinfo.visualid self
  end

  def TkWinfo.visualsavailable(window, includeids=false)
    if includeids
      list(tk_call_without_enc('winfo', 'visualsavailable', 
                               window, "includeids"))
    else
      list(tk_call_without_enc('winfo', 'visualsavailable', window))
    end
  end
  def winfo_visualsavailable(includeids=false)
    TkWinfo.visualsavailable self, includeids
  end

  def TkWinfo.vrootheight(window)
    number(tk_call_without_enc('winfo', 'vrootheight', window))
  end
  def winfo_vrootheight
    TkWinfo.vrootheight self
  end

  def TkWinfo.vrootwidth(window)
    number(tk_call_without_enc('winfo', 'vrootwidth', window))
  end
  def winfo_vrootwidth
    TkWinfo.vrootwidth self
  end

  def TkWinfo.vrootx(window)
    number(tk_call_without_enc('winfo', 'vrootx', window))
  end
  def winfo_vrootx
    TkWinfo.vrootx self
  end

  def TkWinfo.vrooty(window)
    number(tk_call_without_enc('winfo', 'vrooty', window))
  end
  def winfo_vrooty
    TkWinfo.vrooty self
  end

  def TkWinfo.width(window)
    number(tk_call_without_enc('winfo', 'width', window))
  end
  def winfo_width
    TkWinfo.width self
  end

  def TkWinfo.x(window)
    number(tk_call_without_enc('winfo', 'x', window))
  end
  def winfo_x
    TkWinfo.x self
  end

  def TkWinfo.y(window)
    number(tk_call_without_enc('winfo', 'y', window))
  end
  def winfo_y
    TkWinfo.y self
  end

  def TkWinfo.viewable(window)
    bool(tk_call_without_enc('winfo', 'viewable', window))
  end
  def winfo_viewable
    TkWinfo.viewable self
  end

  def TkWinfo.pointerx(window)
    number(tk_call_without_enc('winfo', 'pointerx', window))
  end
  def winfo_pointerx
    TkWinfo.pointerx self
  end

  def TkWinfo.pointery(window)
    number(tk_call_without_enc('winfo', 'pointery', window))
  end
  def winfo_pointery
    TkWinfo.pointery self
  end

  def TkWinfo.pointerxy(window)
    list(tk_call_without_enc('winfo', 'pointerxy', window))
  end
  def winfo_pointerxy
    TkWinfo.pointerxy self
  end
end
