require "tk"

class TkDialog < TkWindow
  extend Tk

  # initialize tk_dialog
  def initialize(keys = nil)
    super()
    @var = TkVariable.new
    id = @var.id

    @title   = title

    @message = message
    @message_config = message_config

    @bitmap  = bitmap
    @bitmap_config = message_config

    @default_button = default_button

    @buttons = buttons
    @button_configs = proc{|num| button_configs num}

    if keys.kind_of? Hash
      @title   = keys['title'] if keys['title']
      @message = keys['message'] if keys['message']
      @bitmap  = keys['bitmap'] if keys['bitmap']
      @default_button = keys['default'] if keys['default']
      @buttons = keys['buttons'] if keys['buttons']

      @command = keys['prev_command']

      @message_config = keys['message_config'] if keys['message_config']
      @bitmap_config  = keys['bitmap_config']  if keys['bitmap_config']
      @button_configs = keys['button_configs'] if keys['button_configs']
    end

    if @title.include? ?\s
      @title = '{' + @title + '}'
    end

    @buttons = tk_split_list(@buttons) if @buttons.kind_of? String
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

    config = ""
    if @message_config.kind_of? Hash
      config << format("%s.msg configure %s\n", 
		       @path, hash_kv(@message_config).join(' '))
    end
    if @bitmap_config.kind_of? Hash
      config << format("%s.msg configure %s\n", 
		       @path, hash_kv(@bitmap_config).join(' '))
    end
    if @button_configs.kind_of? Proc
      @buttons.each_index{|i|
	if (c = @button_configs.call(i)).kind_of? Hash
	  config << format("%s.button%s configure %s\n", 
			   @path, i, hash_kv(c).join(' '))
	end
      }
    end
    config = 'after idle {' + config + '};' if config != ""

    if @command.kind_of? Proc
      @command.call(self)
    end

    INTERP._eval('eval {global '+id+';'+config+
		 'set '+id+' [tk_dialog '+ 
		 @path+" "+@title+" {#{@message}} "+@bitmap+" "+
		 String(@default_button)+" "+@buttons.join(' ')+']}')
  end
  def value
    return @var.value.to_i
  end
  ######################################################
  #                                                    #
  # these methods must be overridden for each dialog   #
  #                                                    #
  ######################################################
  def title
    return "DIALOG"
  end
  def message
    return "MESSAGE"
  end
  def message_config
    return nil
  end
  def bitmap
    return "info"
  end
  def bitmap_config
    return nil
  end
  def default_button
    return 0
  end
  def buttons
    #return "BUTTON1 BUTTON2"
    return ["BUTTON1", "BUTTON2"]
  end
  def button_configs(num)
    return nil
  end
end

#
# dialog for warning
#
class TkWarning < TkDialog
  def initialize(mes)
    @mes = mes
    super()
  end
  def message
    return @mes
  end
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
