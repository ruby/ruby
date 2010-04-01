require 'rdoc/class_module'

##
# A singleton class

class RDoc::SingleClass < RDoc::ClassModule

  def ancestors
    includes + [superclass]
  end

end

