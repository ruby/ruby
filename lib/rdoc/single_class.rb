require 'rdoc/class_module'

##
# A singleton class

class RDoc::SingleClass < RDoc::ClassModule

  # Adds the superclass to the included modules.
  def ancestors
    superclass ? super + [superclass] : super
  end

end

