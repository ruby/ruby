#
#		tkcanvas.rb - Tk canvas classes
#			$Date$
#			by Yukihiro Matsumoto <matz@caelum.co.jp>
#			$Date$
#			by Hidetoshi Nagai <nagai@ai.kyutech.ac.jp>

require "tk"
require 'tkfont'

module TkTreatCItemFont
  def tagfont_configinfo(tagOrId)
    if tagOrId.kind_of?(TkcItem) || tagOrId.kind_of?(TkcTag)
      pathname = self.path + ';' + tagOrId.id.to_s
    else
      pathname = self.path + ';' + tagOrId.to_s
    end
    ret = TkFont.used_on(pathname)
    if ret == nil
      ret = TkFont.init_widget_font(pathname, 
				    self.path, 'itemconfigure', tagOrId)
    end
    ret
  end
  alias tagfontobj tagfont_configinfo

  def tagfont_configure(tagOrId, slot)
    if tagOrId.kind_of?(TkcItem) || tagOrId.kind_of?(TkcTag)
      pathname = self.path + ';' + tagOrId.id.to_s
    else
      pathname = self.path + ';' + tagOrId.to_s
    end
    if (fnt = slot['font'])
      slot['font'] = nil
      if fnt.kind_of? TkFont
	return fnt.call_font_configure(pathname, 
				       self.path,'itemconfigure',tagOrId,slot)
      else
	latintagfont_configure(tagOrId, fnt) if fnt
      end
    end
    if (ltn = slot['latinfont'])
      slot['latinfont'] = nil
      latintagfont_configure(tagOrId, ltn) if ltn
    end
    if (ltn = slot['asciifont'])
      slot['asciifont'] = nil
      latintagfont_configure(tagOrId, ltn) if ltn
    end
    if (knj = slot['kanjifont'])
      slot['kanjifont'] = nil
      kanjitagfont_configure(tagOrId, knj) if knj
    end

    tk_call(self.path, 'itemconfigure', tagOrId, *hash_kv(slot)) if slot != {}
    self
  end

  def latintagfont_configure(tagOrId, ltn, keys=nil)
    fobj = tagfontobj(tagOrId)
    if ltn.kind_of? TkFont
      conf = {}
      ltn.latin_configinfo.each{|key,val| conf[key] = val if val != []}
      if conf == {}
	fobj.latin_replace(ltn)
	fobj.latin_configure(keys) if keys
      elsif keys
	fobj.latin_configure(conf.update(keys))
      else
	fobj.latin_configure(conf)
      end
    else
      fobj.latin_replace(ltn)
    end
  end
  alias asciitagfont_configure latintagfont_configure

  def kanjitagfont_configure(tagOrId, knj, keys=nil)
    fobj = tagfontobj(tagOrId)
    if knj.kind_of? TkFont
      conf = {}
      knj.kanji_configinfo.each{|key,val| conf[key] = val if val != []}
      if conf == {}
	fobj.kanji_replace(knj)
	fobj.kanji_configure(keys) if keys
      elsif keys
	fobj.kanji_configure(conf.update(keys))
      else
	fobj.kanji_configure(conf)
      end
    else
      fobj.kanji_replace(knj)
    end
  end

  def tagfont_copy(tagOrId, window, wintag=nil)
    if wintag
      window.tagfontobj(wintag).configinfo.each{|key,value|
	tagfontobj(tagOrId).configure(key,value)
      }
      tagfontobj(tagOrId).replace(window.tagfontobj(wintag).latin_font, 
				  window.tagfontobj(wintag).kanji_font)
    else
      window.tagfont(tagOrId).configinfo.each{|key,value|
	tagfontobj(tagOrId).configure(key,value)
      }
      tagfontobj(tagOrId).replace(window.fontobj.latin_font, 
				  window.fontobj.kanji_font)
    end
  end

  def latintagfont_copy(tagOrId, window, wintag=nil)
    if wintag
      tagfontobj(tagOrId).latin_replace(window.tagfontobj(wintag).latin_font)
    else
      tagfontobj(tagOrId).latin_replace(window.fontobj.latin_font)
    end
  end
  alias asciitagfont_copy latintagfont_copy

  def kanjitagfont_copy(tagOrId, window, wintag=nil)
    if wintag
      tagfontobj(tagOrId).kanji_replace(window.tagfontobj(wintag).kanji_font)
    else
      tagfontobj(tagOrId).kanji_replace(window.fontobj.kanji_font)
    end
  end
end

class TkCanvas<TkWindow
  include TkTreatCItemFont

  WidgetClassName = 'Canvas'.freeze
  TkClassBind::WidgetClassNameTBL[WidgetClassName] = self
  def self.to_eval
    WidgetClassName
  end

  def create_self
    tk_call 'canvas', path
  end

  def tagid(tag)
    if tag.kind_of?(TkcItem) || tag.kind_of?(TkcTag)
      tag.id
    else
      tag
    end
  end
  private :tagid

  def addtag(tag, mode, *args)
    tk_send 'addtag', tagid(tag), mode, *args
  end
  def addtag_above(tagOrId, target)
    addtag(tagOrId, 'above', tagid(target))
  end
  def addtag_all(tagOrId)
    addtag(tagOrId, 'all')
  end
  def addtag_below(tagOrId, target)
    addtag(tagOrId, 'below', tagid(target))
  end
  def addtag_closest(tagOrId, x, y, halo=None, start=None)
    addtag(tagOrId, 'closest', x, y, halo, start)
  end
  def addtag_enclosed(tagOrId, x1, y1, x2, y2)
    addtag(tagOrId, 'enclosed', x1, y1, x2, y2)
  end
  def addtag_overlapping(tagOrId, x1, y1, x2, y2)
    addtag(tagOrId, 'overlapping', x1, y1, x2, y2)
  end
  def addtag_withtag(tagOrId, tag)
    addtag(tagOrId, 'withtag', tagid(tag))
  end

  def bbox(tagOrId, *tags)
    list(tk_send('bbox', tagid(tagOrId), *tags))
  end

  def itembind(tag, context, cmd=Proc.new, args=nil)
    id = install_bind(cmd, args)
    begin
      tk_send 'bind', tagid(tag), "<#{tk_event_sequence(context)}>", id
    rescue
      uninstall_cmd(cmd)
      fail
    end
    # @cmdtbl.push id
  end

  def itembindinfo(tag, context=nil)
    if context
      (tk_send('bind', tagid(tag), 
	       "<#{tk_event_sequence(context)}>")).collect{|cmdline|
	if cmdline =~ /^rb_out (c\d+)\s+(.*)$/
	  [Tk_CMDTBL[$1], $2]
	else
	  cmdline
	end
      }
    else
      tk_split_list(tk_send 'bind', tagid(tag)).filter{|seq|
	seq[1..-2].gsub(/></,',')
      }
    end
  end

  def canvasx(x, *args)
    tk_tcl2ruby(tk_send 'canvasx', x, *args)
  end
  def canvasy(y, *args)
    tk_tcl2ruby(tk_send 'canvasy', y, *args)
  end

  def coords(tag, *args)
    if args == []
      tk_split_list(tk_send('coords', tagid(tag)))
    else
      tk_send('coords', tagid(tag), *args)
    end
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

  def find(mode, *args)
    list(tk_send 'find', mode, *args).filter{|id| 
      TkcItem.id2obj(id)
    }
  end
  def find_above(target)
    find('above', tagid(target))
  end
  def find_all
    find('all')
  end
  def find_below(target)
    find('below', tagid(target))
  end
  def find_closest(x, y, halo=None, start=None)
    find('closest', x, y, halo, start)
  end
  def find_enclosed(x1, y1, x2, y2)
    find('enclosed', x1, y1, x2, y2)
  end
  def find_overlapping(x1, y1, x2, y2)
    find('overlapping', x1, y1, x2, y2)
  end
  def find_withtag(tag)
    find('withtag', tag)
  end

  def itemfocus(tagOrId=nil)
    if tagOrId
      tk_send 'focus', tagid(tagOrId)
    else
      ret = tk_send('focus')
      if ret == ""
	nil
      else
	TkcItem.id2obj(ret)
      end
    end
  end

  def gettags(tagOrId)
    list(tk_send('gettags', tagid(tagOrId))).collect{|tag|
      TkcTag.id2obj(tag)
    }
  end

  def icursor(tagOrId, index)
    tk_send 'icursor', tagid(tagOrId), index
  end

  def index(tagOrId, index)
    tk_send 'index', tagid(tagOrId), index
  end

  def insert(tagOrId, index, string)
    tk_send 'insert', tagid(tagOrId), index, string
  end

  def itemcget(tagOrId, option)
    tk_tcl2ruby tk_send 'itemcget', tagid(tagOrId), "-#{option}"
  end

  def itemconfigure(tagOrId, key, value=None)
    if key.kind_of? Hash
      if ( key['font'] || key['kanjifont'] \
	  || key['latinfont'] || key['asciifont'] )
	tagfont_configure(tagOrId, key.dup)
      else
	tk_send 'itemconfigure', tagid(tagOrId), *hash_kv(key)
      end

    else
      if ( key == 'font' || key == 'kanjifont' \
	  || key == 'latinfont' || key == 'asciifont' )
	tagfont_configure(tagid(tagOrId), {key=>value})
      else
	tk_call 'itemconfigure', tagid(tagOrId), "-#{key}", value
      end
    end
  end
#  def itemconfigure(tagOrId, key, value=None)
#    if key.kind_of? Hash
#      tk_send 'itemconfigure', tagid(tagOrId), *hash_kv(key)
#    else
#      tk_send 'itemconfigure', tagid(tagOrId), "-#{key}", value
#    end
#  end
#  def itemconfigure(tagOrId, keys)
#    tk_send 'itemconfigure', tagid(tagOrId), *hash_kv(keys)
#  end

  def itemconfiginfo(tagOrId, key=nil)
    if key
      conf = tk_split_list(tk_send 'itemconfigure', tagid(tagOrId), "-#{key}")
      conf[0] = conf[0][1..-1]
      conf
    else
      tk_split_list(tk_send 'itemconfigure', tagid(tagOrId)).collect{|conf|
	conf[0] = conf[0][1..-1]
	conf
      }
    end
  end

  def lower(tag, below=None)
    tk_send 'lower', tagid(tag), below
  end

  def move(tag, x, y)
    tk_send 'move', tagid(tag), x, y
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

  def select(mode, *args)
    tk_send 'select', mode, *args
  end
  def select_adjust(tagOrId, index)
    select('adjust', tagid(tagOrId), index)
  end
  def select_clear
    select('clear')
  end
  def select_from(tagOrId, index)
    select('from', tagid(tagOrId), index)
  end
  def select_item
    select('item')
  end
  def select_to(tagOrId, index)
    select('to', tagid(tagOrId), index)
  end

  def itemtype(tag)
    TkcItem.type2class(tk_send 'type', tagid(tag))
  end

  def xview(*index)
    tk_send 'xview', *index
  end
  def yview(*index)
    tk_send 'yview', *index
  end
end

module TkcTagAccess
  include TkComm
  include TkTreatTagFont

  def addtag(tag)
    @c.addtag(tag, 'with', @id)
  end

  def bbox
    @c.bbox(@id)
  end

  def bind(seq, cmd=Proc.new, args=nil)
    @c.itembind @id, seq, cmd, args
  end

  def bindinfo(seq=nil)
    @c.itembindinfo @id, seq
  end

  def cget(option)
    @c.itemcget @id, option
  end

  def configure(key, value=None)
    @c.itemconfigure @id, key, value
  end
#  def configure(keys)
#    @c.itemconfigure @id, keys
#  end

  def configinfo(key=nil)
    @c.itemconfiginfo @id, key
  end

  def coords(*args)
    @c.coords @id, *args
  end

  def dchars(first, last=None)
    @c.dchars @id, first, last
  end

  def dtag(tag_to_del=None)
    @c.dtag @id, tag_to_del
  end

  def find
    @c.find 'withtag', @id
  end
  alias list find

  def focus
    @c.itemfocus @id
  end

  def gettags
    @c.gettags @id
  end

  def icursor(index)
    @c.icursor @id, index
  end

  def index(index)
    @c.index @id, index
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

  def select_adjust(index)
    @c.select('adjust', @id, index)
  end
  def select_from(index)
    @c.select('from', @id, index)
  end
  def select_to(index)
    @c.select('to', @id, index)
  end

  def itemtype
    @c.itemtype @id
  end
end

class TkcTag<TkObject
  include TkcTagAccess

  CTagID_TBL = {}

  def TkcTag.id2obj(id)
    CTagID_TBL[id]? CTagID_TBL[id]: id
  end

  $tk_canvas_tag = 'ctag0000'
  def initialize(parent, mode=nil, *args)
    if not parent.kind_of?(TkCanvas)
      fail format("%s need to be TkCanvas", parent.inspect)
    end
    @c = parent
    @path = @id = $tk_canvas_tag
    CTagID_TBL[@id] = self
    $tk_canvas_tag = $tk_canvas_tag.succ
    if mode
      tk_call @c.path, "addtag", @id, mode, *args
    end
  end
  def id
    return @id
  end

  def delete
    @c.delete @id
    CTagID_TBL[@id] = nil
  end
  alias remove  delete
  alias destroy delete

  def set_to_above(target)
    @c.addtag_above(@id, target)
  end
  alias above set_to_above

  def set_to_all
    @c.addtag_all(@id)
  end
  alias all set_to_all

  def set_to_below(target)
    @c.addtag_below(@id, target)
  end
  alias below set_to_below

  def set_to_closest(x, y, halo=None, start=None)
    @c.addtag_closest(@id, x, y, halo, start)
  end
  alias closest set_to_closest

  def set_to_enclosed(x1, y1, x2, y2)
    @c.addtag_enclosest(@id, x1, y1, x2, y2)
  end
  alias enclosed set_to_enclosed

  def set_to_overlapping(x1, y1, x2, y2)
    @c.addtag_overlapping(@id, x1, y1, x2, y2)
  end
  alias overlapping set_to_overlapping

  def set_to_withtag(target)
    @c.addtag_withtag(@id, target)
  end
  alias withtag set_to_withtag
end

class TkcTagAll<TkcTag
  def initialize(parent)
    if not parent.kind_of?(TkCanvas)
      fail format("%s need to be TkCanvas", parent.inspect)
    end
    @c = parent
    @path = @id = 'all'
    CTagID_TBL[@id] = self
  end
end

class TkcTagCurrent<TkcTag
  def initialize(parent)
    if not parent.kind_of?(TkCanvas)
      fail format("%s need to be TkCanvas", parent.inspect)
    end
    @c = parent
    @path = @id = 'current'
    CTagID_TBL[@id] = self
  end
end

class TkcGroup<TkcTag
  $tk_group_id = 'tkg00000'
  def create_self(parent, *args)
    if not parent.kind_of?(TkCanvas)
      fail format("%s need to be TkCanvas", parent.inspect)
    end
    @c = parent
    @path = @id = $tk_group_id
    CTagID_TBL[@id] = self
    $tk_group_id = $tk_group_id.succ
    add(*args) if args != []
  end
  
  def include(*tags)
    for i in tags
      i.addtag @id
    end
  end

  def exclude(*tags)
    for i in tags
      i.delete @id
    end
  end
end


class TkcItem<TkObject
  include TkcTagAccess

  CItemTypeToClass = {}
  CItemID_TBL = {}

  def TkcItem.type2class(type)
    CItemTypeToClass[type]
  end

  def TkcItem.id2obj(id)
    CItemID_TBL[id]? CItemID_TBL[id]: id
  end

  def initialize(parent, *args)
    if not parent.kind_of?(TkCanvas)
      fail format("%s need to be TkCanvas", parent.inspect)
    end
    @parent = @c = parent
    @path = parent.path
    if args[-1].kind_of? Hash
      keys = args.pop
    end
    @id = create_self(*args).to_i ;# 'canvas item id' is integer number
    CItemID_TBL[@id] = self
    if keys
      # tk_call @path, 'itemconfigure', @id, *hash_kv(keys)
      configure(keys) if keys
    end
  end
  def create_self(*args); end
  private :create_self
  def id
    return @id
  end

  def delete
    @c.delete @id
    CItemID_TBL[@id] = nil
  end
  alias remove  delete
  alias destroy delete
end

class TkcArc<TkcItem
  CItemTypeToClass['arc'] = self
  def create_self(*args)
    tk_call(@path, 'create', 'arc', *args)
  end
end
class TkcBitmap<TkcItem
  CItemTypeToClass['bitmap'] = self
  def create_self(*args)
    tk_call(@path, 'create', 'bitmap', *args)
  end
end
class TkcImage<TkcItem
  CItemTypeToClass['image'] = self
  def create_self(*args)
    tk_call(@path, 'create', 'image', *args)
  end
end
class TkcLine<TkcItem
  CItemTypeToClass['line'] = self
  def create_self(*args)
    tk_call(@path, 'create', 'line', *args)
  end
end
class TkcOval<TkcItem
  CItemTypeToClass['oval'] = self
  def create_self(*args)
    tk_call(@path, 'create', 'oval', *args)
  end
end
class TkcPolygon<TkcItem
  CItemTypeToClass['polygon'] = self
  def create_self(*args)
    tk_call(@path, 'create', 'polygon', *args)
  end
end
class TkcRectangle<TkcItem
  CItemTypeToClass['rectangle'] = self
  def create_self(*args)
    tk_call(@path, 'create', 'rectangle', *args)
  end
end
class TkcText<TkcItem
  CItemTypeToClass['text'] = self
  def create_self(*args)
    tk_call(@path, 'create', 'text', *args)
  end
end
class TkcWindow<TkcItem
  CItemTypeToClass['window'] = self
  def create_self(*args)
    tk_call(@path, 'create', 'window', *args)
  end
end

class TkImage<TkObject
  include Tk

  Tk_IMGTBL = {}

  $tk_image_id = 'i00000'
  def initialize(keys=nil)
    @path = $tk_image_id
    $tk_image_id = $tk_image_id.succ
    tk_call 'image', 'create', @type, @path, *hash_kv(keys)
    Tk_IMGTBL[@path] = self
  end

  def delete
    Tk_IMGTBL[@id] = nil if @id
    tk_call('image', 'delete', @path)
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
    Tk.tk_call('image', 'names').split.filter{|id|
      (Tk_IMGTBL[id])? Tk_IMGTBL[id] : id
    }
  end

  def TkImage.types
    Tk.tk_call('image', 'types').split
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

  def cget(option)
    tk_tcl2ruby tk_send 'cget', option
  end

  def copy(source, *opts)
    args = opts.collect{|term|
      if term.kind_of?(String) && term.include?(?\s)
	term.split
      else
	term
      end
    }.flatten

    tk_send 'copy', source, *args
  end

  def get(x, y)
    tk_send 'get', x, y
  end

  def put(data, *to)
    if to == []
      tk_send 'put', data
    else
      tk_send 'put', data, '-to', *to
    end
  end

  def read(file, *opts)
    args = opts.collect{|term|
      if term.kind_of?(String) && term.include?(?\s)
	term.split
      else
	term
      end
    }.flatten
  
    tk_send 'read', file, *args
  end

  def redither
    tk_send 'redither'
  end

  def write(file, *opts)
    args = opts.collect{|term|
      if term.kind_of?(String) && term.include?(?\s)
	term.split
      else
	term
      end
    }.flatten
  
    tk_send 'write', file, *args
  end
end
