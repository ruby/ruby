#
# tk/image.rb : treat Tk image objects
#

require 'tk'

class TkImage<TkObject
  include Tk

  TkCommandNames = ['image'.freeze].freeze

  Tk_IMGTBL = TkCore::INTERP.create_table
  Tk_Image_ID = ['i'.freeze, '00000'.taint].freeze

  TkCore::INTERP.init_ip_env{ Tk_IMGTBL.clear }

  def initialize(keys=nil)
    # @path = Tk_Image_ID.join('')
    @path = Tk_Image_ID.join(TkCore::INTERP._ip_id_)
    Tk_Image_ID[1].succ!
    tk_call_without_enc('image', 'create', @type, @path, *hash_kv(keys, true))
    Tk_IMGTBL[@path] = self
  end

  def delete
    Tk_IMGTBL.delete(@id) if @id
    tk_call_without_enc('image', 'delete', @path)
    self
  end
  def height
    number(tk_call_without_enc('image', 'height', @path))
  end
  def inuse
    bool(tk_call_without_enc('image', 'inuse', @path))
  end
  def itemtype
    tk_call_without_enc('image', 'type', @path)
  end
  def width
    number(tk_call_without_enc('image', 'width', @path))
  end

  def TkImage.names
    Tk.tk_call_without_enc('image', 'names').split.collect!{|id|
      (Tk_IMGTBL[id])? Tk_IMGTBL[id] : id
    }
  end

  def TkImage.types
    Tk.tk_call_without_enc('image', 'types').split
  end
end

class TkBitmapImage<TkImage
  def initialize(*args)
    @type = 'bitmap'
    super
  end
end

class TkPhotoImage<TkImage
  NullArgOptionKeys = [ "shrink", "grayscale" ]

  def _photo_hash_kv(keys)
    keys = _symbolkey2str(keys)
    NullArgOptionKeys.collect{|opt|
      if keys[opt]
        keys[opt] = None
      else
        keys.delete(opt)
      end
    }
    keys.collect{|k,v|
      ['-' << k, v]
    }.flatten
  end
  private :_photo_hash_kv

  def initialize(*args)
    @type = 'photo'
    super
  end

  def blank
    tk_send_without_enc('blank')
    self
  end

  def cget(option)
    case option.to_s
    when 'data', 'file'
      tk_send 'cget', '-' << option.to_s
    else
      tk_tcl2ruby(tk_send('cget', '-' << option.to_s))
    end
  end

  def copy(src, *opts)
    if opts.size == 0
      tk_send('copy', src)
    elsif opts.size == 1 && opts[0].kind_of?(Hash)
      tk_send('copy', src, *_photo_hash_kv(opts[0]))
    else
      # for backward compatibility
      args = opts.collect{|term|
        if term.kind_of?(String) && term.include?(?\s)
          term.split
        else
          term
        end
      }.flatten
      tk_send('copy', src, *args)
    end
    self
  end

  def data(keys={})
    #tk_send('data', *_photo_hash_kv(keys))
    tk_split_list(tk_send('data', *_photo_hash_kv(keys)))
  end

  def get(x, y)
    tk_send('get', x, y).split.collect{|n| n.to_i}
  end

  def put(data, *opts)
    if opts == []
      tk_send('put', data)
    elsif opts.size == 1 && opts[0].kind_of?(Hash)
      tk_send('put', data, *_photo_hash_kv(opts[0]))
    else
      # for backward compatibility
      tk_send('put', data, '-to', *opts)
    end
    self
  end

  def read(file, *opts)
    if opts.size == 0
      tk_send('read', file)
    elsif opts.size == 1 && opts[0].kind_of?(Hash)
      tk_send('read', file, *_photo_hash_kv(opts[0]))
    else
      # for backward compatibility
      args = opts.collect{|term|
        if term.kind_of?(String) && term.include?(?\s)
          term.split
        else
          term
        end
      }.flatten
      tk_send('read', file, *args)
    end
    self
  end

  def redither
    tk_send 'redither'
    self
  end

  def get_transparency(x, y)
    bool(tk_send('transparency', 'get', x, y))
  end
  def set_transparency(x, y, st)
    tk_send('transparency', 'set', x, y, st)
    self
  end

  def write(file, *opts)
    if opts.size == 0
      tk_send('write', file)
    elsif opts.size == 1 && opts[0].kind_of?(Hash)
      tk_send('write', file, *_photo_hash_kv(opts[0]))
    else
      # for backward compatibility
      args = opts.collect{|term|
        if term.kind_of?(String) && term.include?(?\s)
          term.split
        else
          term
        end
      }.flatten
      tk_send('write', file, *args)
    end
    self
  end
end
