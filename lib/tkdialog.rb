require "tk"

class TkDialog < TkWindow
  # initialize tk_dialog
  def initialize
    super
    @var = TkVariable.new
    id = @var.id
    INTERP._eval('eval {global '+id+';'+
		 'set '+id+' [tk_dialog '+ 
		 @path+" "+title+" \"#{message}\" "+bitmap+" "+
		 default_button+" "+buttons+']}')
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
  def bitmap
    return "info"
  end
  def default_button
    return 0
  end
  def buttons
    return "BUTTON1 BUTTON2"
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
