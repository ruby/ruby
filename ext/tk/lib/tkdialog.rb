require "tk"

class TkDialog2 < TkWindow
  extend Tk

  TkCommandNames = ['tk_dialog'.freeze].freeze

  def self.show(*args)
    dlog = self.new(*args)
    dlog.show
    dlog
  end

  def _set_button_config(configs)
    set_config = proc{|c,i|
      if $VERBOSE && (c.has_key?('command') || c.has_key?(:command))
	STDERR.print("Warning: cannot give a command option " + 
		     "to the dialog button#{i}. It was removed.\n")
      end
      c.delete('command'); c.delete(:command)
      @config << format("%s.button%s configure %s; ", 
			@path, i, hash_kv(c).join(' '))
    }
    case configs
    when Proc
      @buttons.each_index{|i|
	if (c = configs.call(i)).kind_of? Hash
	  set_config.call(c,i)
	end
      }

    when Array
      @buttons.each_index{|i|
	if (c = configs[i]).kind_of? Hash
	  set_config.call(c,i)
	end
      }

    when Hash
      @buttons.each_with_index{|s,i|
	if (c = configs[s]).kind_of? Hash
	  set_config.call(c,i)
	end
      }
    end
    @config = 'after idle {' + @config + '};' if @config != ""
  end
  private :_set_button_config

  # initialize tk_dialog
  def initialize(keys = nil)
    super()

    @var = TkVariable.new

    @title   = title

    @message = message
    @message_config = message_config
    @msgframe_config = msgframe_config

    @bitmap  = bitmap
    @bitmap_config = message_config

    @default_button = default_button

    @buttons = buttons
    @button_configs = proc{|num| button_configs(num)}
    @btnframe_config = btnframe_config

    #@config = "puts [winfo children .w0000];"
    @config = ""

    @command = nil

    if keys.kind_of? Hash
      keys = _symbolkey2str(keys)
      @title   = keys['title'] if keys.key? 'title'
      @message = keys['message'] if keys.key? 'message'
      @bitmap  = keys['bitmap'] if keys.key? 'bitmap'
      @bitmap  = '{}' if @bitmap == nil || @bitmap == ""
      @default_button = keys['default'] if keys.key? 'default'
      @buttons = keys['buttons'] if keys.key? 'buttons'

      @command = keys['prev_command']

      @message_config = keys['message_config'] if keys.key? 'message_config'
      @msgframe_config = keys['msgframe_config'] if keys.key? 'msgframe_config'
      @bitmap_config  = keys['bitmap_config']  if keys.key? 'bitmap_config'
      @button_configs = keys['button_configs'] if keys.key? 'button_configs'
      @btnframe_config = keys['btnframe_config'] if keys.key? 'btnframe_config'
    end

    if @title.include? ?\s
      @title = '{' + @title + '}'
    end

    if @buttons.kind_of? Array
      _set_button_config(@buttons.collect{|cfg| 
			   (cfg.kind_of? Array)? cfg[1]: nil})
      @buttons = @buttons.collect{|cfg| (cfg.kind_of? Array)? cfg[0]: cfg}
    end
    if @buttons.kind_of? Hash 
      _set_button_config(@buttons)
      @buttons = @buttons.keys
    end
    @buttons = tk_split_simplelist(@buttons) if @buttons.kind_of? String
    @buttons = @buttons.collect{|s|
      if s.kind_of? Array
	s = s.join(' ')
      end
      if s.include? ?\s
	'{' + s + '}'
      else
	s
      end
    }

    if @message_config.kind_of? Hash
      @config << format("%s.msg configure %s;", 
		       @path, hash_kv(@message_config).join(' '))
    end

    if @msgframe_config.kind_of? Hash
      @config << format("%s.top configure %s;", 
		       @path, hash_kv(@msgframe_config).join(' '))
    end

    if @btnframe_config.kind_of? Hash
      @config << format("%s.bot configure %s;", 
		       @path, hash_kv(@btnframe_config).join(' '))
    end

    if @bitmap_config.kind_of? Hash
      @config << format("%s.bitmap configure %s;", 
		       @path, hash_kv(@bitmap_config).join(' '))
    end

    _set_button_config(@button_configs) if @button_configs

    if @command.kind_of? Proc
      @command.call(self)
    end
  end

  def show
    if @default_button.kind_of? String
      default_button = @buttons.index(@default_button)
    else
      default_button = @default_button
    end
    default_button = '{}' if default_button == nil
    Tk.ip_eval('eval {global '+@var.id+';'+@config+
	       'set '+@var.id+' [tk_dialog '+ 
	       @path+" "+@title+" {#{@message}} "+@bitmap+" "+
	       String(default_button)+" "+@buttons.join(' ')+']}')
  end

  def value
    return @var.value.to_i
  end
  ######################################################
  #                                                    #
  # these methods must be overridden for each dialog   #
  #                                                    #
  ######################################################
  private

  def title
    # returns a title string of the dialog window
    return "DIALOG"
  end
  def message
    # returns a message text to display on the dialog
    return "MESSAGE"
  end
  def message_config
    # returns a Hash {option=>value, ...} for the message text
    return nil
  end
  def msgframe_config
    # returns a Hash {option=>value, ...} for the message text frame
    return nil
  end
  def bitmap
    # returns a bitmap name or a bitmap file path 
    # (@ + path ; e.g. '@/usr/share/bitmap/sample.xbm')
    return "info"
  end
  def bitmap_config
    # returns nil or a Hash {option=>value, ...} for the bitmap
    return nil
  end
  def default_button
    # returns a default button's number or name
    # if nil or null string, set no-default
    return 0
  end
  def buttons
    #return "BUTTON1 BUTTON2"
    return ["BUTTON1", "BUTTON2"]
  end
  def button_configs(num)
    # returns nil / Proc / Array or Hash (see _set_button_config)
    return nil
  end
  def btnframe_config
    # returns nil or a Hash {option=>value, ...} for the button frame
    return nil
  end
end


#
# TkDialog : with showing at initialize
#
class TkDialog < TkDialog2
  def self.show(*args)
    self.new(*args)
  end

  def initialize(*args)
    super(*args)
    show
  end
end


#
# dialog for warning
#
class TkWarning2 < TkDialog2
  def initialize(mes)
    super(:message=>mes)
  end

  def show(mes = nil)
    mes_bup = @message
    @message = mes if mes
    ret = super()
    @message = mes_bup
    ret
  end

  #######
  private

  def title
    return "WARNING";
  end
  def bitmap
    return "warning";
  end
  def default_button
    return 0;
  end
  def buttons
    return "OK";
  end
end

class TkWarning < TkWarning2
  def self.show(*args)
    self.new(*args)
  end
  def initialize(mes)
    super(mes)
    show
  end
end
