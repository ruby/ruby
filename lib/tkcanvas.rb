#
#		tkcanvas.rb - Tk canvas classes
#			$Date: 1995/11/11 11:17:15 $
#			by Yukihiro Matsumoto <matz@caelum.co.jp>

require "tk"

class TkCanvas<TkWindow
  def create_self
    tk_call 'canvas', path
  end
  def tagid(tag)
    if tag.kind_of?(TkcItem)
      tag.id
    else
      tag
    end
  end
  private :tagid
  def addtag(tag, *args)
    tk_send 'addtag', tagid(tag), *args
  end
  def addtag_above(tagOrId)
    addtag('above', tagOrId)
  end
  def addtag_all
    addtag('all')
  end
  def addtag_below(tagOrId)
    addtag('below', tagOrId)
  end
  def addtag_closest(x, y, halo=None, start=None)
    addtag('closest', x, y, halo, start)
  end
  def addtag_enclosed(x1, y1, x2, y2)
    addtag('enclosed', x1, y1, x2, y2)
  end
  def addtag_overlapping(x1, y1, x2, y2)
    addtag('overlapping', x1, y1, x2, y2)
  end
  def addtag_withtag(tagOrId)
    addtag('withtag', tagOrId)
  end
  def bbox(tag)
    list(tk_send('bbox', tagid(tag)))
  end
  def itembind(tag, seq, cmd=Proc.new)
    id = install_cmd(cmd)
    tk_send 'bind', tagid(tag), "<#{seq}>", id
    @cmdtbl.push id
  end
  def canvasx(x, *args)
    tk_send 'canvasx', x, *args
  end
  def canvasy(y, *args)
    tk_send 'canvasy', y, *args
  end
  def coords(tag, *args)
    tk_send 'coords', tagid(tag), *args
  end
  def dchars(tag, first, last=None)
    tk_send 'dchars', tagid(tag), first, last
  end
  def delete(*args)
    tk_send 'delete', *args
  end
  alias remove delete
  def dtag(tag, tag_to_del=None)
    tk_send 'dtag', tagid(tag), tag_to_del
  end
  def find(*args)
    tk_send 'find', *args
  end
  def itemfocus(tag)
    tk_send 'find', tagid(tag)
  end
  def gettags(tag)
    tk_send 'gettags', tagid(tag)
  end
  def icursor(tag, index)
    tk_send 'icursor', tagid(tag), index
  end
  def index(tag)
    tk_send 'index', tagid(tag), index
  end
 def lower(tag, below=None)
    tk_send 'lower', tagid(tag), below
  end
  def move(tag, x, y)
    tk_send 'move', tagid(tag), x, y
  end
  def itemtype(tag)
    tk_send 'type', tagid(tag)
  end
  def postscript(keys)
    tk_send "postscript", *hash_kv(keys)
  end
  def raise(tag, above=None)
    tk_send 'raise', tagid(tag), above
  end
  def scale(tag, x, y, xs, ys)
    tk_send 'scale', tagid(tag), x, y, xs, ys
  end
  def scan_mark(x, y)
    tk_send 'scan', 'mark', x, y
  end
  def scan_dragto(x, y)
    tk_send 'scan', 'dragto', x, y
  end
  def select(*args)
    tk_send 'select', *args
  end
  def xview(*index)
    tk_send 'xview', *index
  end
  def yview(*index)
    tk_send 'yview', *index
  end
end

class TkcItem<TkObject
  def initialize(parent, *args)
    if not parent.kind_of?(TkCanvas)
      fail format("%s need to be TkCanvas", parent.inspect)
    end
    @c = parent
    @path = parent.path
    if args[-1].kind_of? Hash
      keys = args.pop
    end
    @id = create_self(*args)
    if keys
      tk_call @path, 'itemconfigure', @id, *hash_kv(keys)
    end
  end
  def create_self(*args) end
  private :create_self
  def id
    return @id
  end

  def configure(slot, value)
    tk_call path, 'itemconfigure', @id, "-#{slot}", value
  end

  def addtag(tag)
    @c.addtag(tag, 'withtag', @id)
  end
  def bbox
    @c.bbox(@id)
  end
  def bind(seq, cmd=Proc.new)
    @c.itembind @id, seq, cmd
  end
  def coords(*args)
    @c.coords @id, *args
  end
  def dchars(first, last=None)
    @c.dchars @id, first, last
  end
  def dtag(ttd)
    @c.dtag @id, ttd
  end
  def focus
    @c.focus @id
  end
  def gettags
    @c.gettags @id
  end
  def icursor
    @c.icursor @id
  end
  def index
    @c.index @id
  end
  def insert(beforethis, string)
    @c.insert @id, beforethis, string
  end
  def lower(belowthis=None)
    @c.lower @id, belowthis
  end
  def move(xamount, yamount)
    @c.move @id, xamount, yamount
  end
  def raise(abovethis=None)
    @c.raise @id, abovethis
  end
  def scale(xorigin, yorigin, xscale, yscale)
    @c.scale @id, xorigin, yorigin, xscale, yscale
  end
  def itemtype
    @c.itemtype @id
  end
  def destroy
    tk_call path, 'delete', @id
  end
end

class TkcArc<TkcItem
  def create_self(*args)
    tk_call(@path, 'create', 'arc', *args)
  end
end
class TkcBitmap<TkcItem
  def create_self(*args)
    tk_call(@path, 'create', 'bitmap', *args)
  end
end
class TkcImage<TkcItem
  def create_self(*args)
    tk_call(@path, 'create', 'image', *args)
  end
end
class TkcLine<TkcItem
  def create_self(*args)
    tk_call(@path, 'create', 'line', *args)
  end
end
class TkcOval<TkcItem
  def create_self(*args)
    tk_call(@path, 'create', 'oval', *args)
  end
end
class TkcPolygon<TkcItem
  def create_self(*args)
    tk_call(@path, 'create', 'polygon', *args)
  end
end
class TkcRectangle<TkcItem
  def create_self(*args)
    tk_call(@path, 'create', 'rectangle', *args)
  end
end
class TkcText<TkcItem
  def create_self(*args)
    tk_call(@path, 'create', 'text', *args)
  end
end
class TkcWindow<TkcItem
  def create_self(*args)
    tk_call(@path, 'create', 'window', *args)
  end
end
class TkcGroup<TkcItem
  $tk_group_id = 'tkg00000'
  def create_self(*args)
    @id = $tk_group_id
    $tk_group_id = $tk_group_id.succ
  end
  
  def add(*tags)
    for i in tags
      i.addtag @id
    end
  end
  def add(*tags)
    for i in tags
      i.addtag @id
    end
  end
  def delete(*tags)
    for i in tags
      i.delete @id
    end
  end
  def list
    @c.find 'withtag', @id
  end
  alias remove delete
end


class TkImage<TkObject
  include Tk

  $tk_image_id = 'i00000'
  def initialize(keys=nil)
    @path = $tk_image_id
    $tk_image_id = $tk_image_id.succ
    tk_call 'image', 'create', @type, @path, *hash_kv(keys)
  end

  def height
    number(tk_call('image', 'height', @path))
  end
  def itemtype
    tk_call('image', 'type', @path)
  end
  def width
    number(tk_call('image', 'height', @path))
  end

  def TkImage.names
    tk_call('image', 'names', @path).split
  end
  def TkImage.types
    tk_call('image', 'types', @path).split
  end
end

class TkBitmapImage<TkImage
  def initialize(*args)
    @type = 'bitmap'
    super
  end
end

class TkPhotoImage<TkImage
  def initialize(*args)
    @type = 'photo'
    super
  end

  def blank
    tk_send 'blank'
  end
  def cget
    tk_send 'cget'
  end
  def get(x, y)
    tk_send 'get', x, y
  end
  def put(data, to=None)
    tk_send 'put', data, to
  end
end
