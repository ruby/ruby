#
# tk/itemfont.rb : control font of widget items
#
require 'tk'

module TkTreatItemFont
  def __conf_cmd(idx)
    raise NotImplementedError, "need to define `__conf_cmd'"
  end
  def __item_pathname(tagOrId)
    raise NotImplementedError, "need to define `__item_pathname'"
  end
  private :__conf_cmd, :__item_pathname

  def tagfont_configinfo(tagOrId, name = nil)
    pathname = __item_pathname(tagOrId)
    ret = TkFont.used_on(pathname)
    if ret == nil
=begin
      if name
	ret = name
      else
	ret = TkFont.init_widget_font(pathname, self.path, 
				      __conf_cmd(0), __conf_cmd(1), tagOrId)
      end
=end
      ret = TkFont.init_widget_font(pathname, self.path, 
				    __conf_cmd(0), __conf_cmd(1), tagOrId)
    end
    ret
  end
  alias tagfontobj tagfont_configinfo

  def tagfont_configure(tagOrId, slot)
    pathname = __item_pathname(tagOrId)
    slot = _symbolkey2str(slot)

    if slot.key?('font')
      fnt = slot.delete('font')
      if fnt.kind_of? TkFont
	return fnt.call_font_configure(pathname, self.path,
				       __conf_cmd(0), __conf_cmd(1), 
				       tagOrId, slot)
      else
	if fnt 
	  if (slot.key?('kanjifont') || 
	      slot.key?('latinfont') || 
	      slot.key?('asciifont'))
	    fnt = TkFont.new(fnt)

	    lfnt = slot.delete('latinfont')
	    lfnt = slot.delete('asciifont') if slot.key?('asciifont')
	    kfnt = slot.delete('kanjifont')

	    fnt.latin_replace(lfnt) if lfnt
	    fnt.kanji_replace(kfnt) if kfnt
	  end

	  slot['font'] = fnt
	  tk_call(self.path, __conf_cmd(0), __conf_cmd(1), 
		  tagOrId, *hash_kv(slot))
	end
	return self
      end
    end

    lfnt = slot.delete('latinfont')
    lfnt = slot.delete('asciifont') if slot.key?('asciifont')
    kfnt = slot.delete('kanjifont')

    if lfnt && kfnt
      return TkFont.new(lfnt, kfnt).call_font_configure(pathname, self.path,
							__conf_cmd(0), 
							__conf_cmd(1), 
							tagOrId, slot)
    end

    latintagfont_configure(tagOrId, lfnt) if lfnt
    kanjitagfont_configure(tagOrId, kfnt) if kfnt
      
    tk_call(self.path, __conf_cmd(0), __conf_cmd(1), 
	    tagOrId, *hash_kv(slot)) if slot != {}
    self
  end

  def latintagfont_configure(tagOrId, ltn, keys=nil)
    pathname = __item_pathname(tagOrId)
    if (fobj = TkFont.used_on(pathname))
      fobj = TkFont.new(fobj)    # create a new TkFont object
    elsif Tk::JAPANIZED_TK
      fobj = tagfontobj(tagOrId) # create a new TkFont object
    else
      tk_call(self.path, __conf_cmd(0), __conf_cmd(1), tagOrId, '-font', ltn)
      return self
    end

    if fobj.kind_of?(TkFont)
      if ltn.kind_of? TkFont
	conf = {}
	ltn.latin_configinfo.each{|key,val| conf[key] = val}
	if keys
	  fobj.latin_configure(conf.update(keys))
	else
	  fobj.latin_configure(conf)
	end
      else
	fobj.latin_replace(ltn)
      end
    end

    return fobj.call_font_configure(pathname, self.path,
				    __conf_cmd(0), __conf_cmd(1), tagOrId, {})
  end
  alias asciitagfont_configure latintagfont_configure

  def kanjitagfont_configure(tagOrId, knj, keys=nil)
    pathname = __item_pathname(tagOrId)
    if (fobj = TkFont.used_on(pathname))
      fobj = TkFont.new(fobj)    # create a new TkFont object
    elsif Tk::JAPANIZED_TK
      fobj = tagfontobj(tagOrId) # create a new TkFont object
    else
      tk_call(self.path, __conf_cmd(0), __conf_cmd(1), tagOrId, '-font', knj)
      return self
    end

    if fobj.kind_of?(TkFont)
      if knj.kind_of? TkFont
	conf = {}
	knj.kanji_configinfo.each{|key,val| conf[key] = val}
	if keys
	  fobj.kanji_configure(conf.update(keys))
	else
	  fobj.kanji_configure(conf)
	end
      else
	fobj.kanji_replace(knj)
      end
    end

    return fobj.call_font_configure(pathname, self.path,
				    __conf_cmd(0), __conf_cmd(1), tagOrId, {})
  end

  def tagfont_copy(tagOrId, window, wintag=nil)
    pathname = __item_pathname(tagOrId)
    if wintag
      fnt = window.tagfontobj(wintag).dup
    else
      fnt = window.fontobj.dup
    end
    fnt.call_font_configure(pathname, self.path, 
			    __conf_cmd(0), __conf_cmd(1), tagOrId, {})
    return self
  end

  def latintagfont_copy(tagOrId, window, wintag=nil)
    pathname = __item_pathname(tagOrId)
    tagfontobj(tagOrId).dup.call_font_configure(pathname, self.path, 
						__conf_cmd(0), __conf_cmd(1), 
						tagOrId, {})
    if wintag
      tagfontobj(tagOrId).
	latin_replace(window.tagfontobj(wintag).latin_font_id)
    else
      tagfontobj(tagOrId).latin_replace(window.fontobj.latin_font_id)
    end
    self
  end
  alias asciitagfont_copy latintagfont_copy

  def kanjitagfont_copy(tagOrId, window, wintag=nil)
    pathname = __item_pathname(tagOrId)
    tagfontobj(tagOrId).dup.call_font_configure(pathname, self.path, 
						__conf_cmd(0), __conf_cmd(1), 
						tagOrId, {})
    if wintag
      tagfontobj(tagOrId).
	kanji_replace(window.tagfontobj(wintag).kanji_font_id)
    else
      tagfontobj(tagOrId).kanji_replace(window.fontobj.kanji_font_id)
    end
    self
  end
end
