require 'rdoc/class_module'

##
# A normal class, neither singleton nor anonymous

class RDoc::NormalClass < RDoc::ClassModule

  ##
  # Ancestor ClassModules

  def ancestors
    includes + [superclass]
  end

  def inspect # :nodoc:
    superclass = @superclass ? " < #{@superclass}" : nil
    "<%s:0x%x class %s%s includes: %p attributes: %p methods: %p aliases: %p>" % [
      self.class, object_id,
      full_name, superclass, @includes, @attributes, @method_list, @aliases
    ]
  end

  def pretty_print q # :nodoc:
    superclass = @superclass ? " < #{@superclass}" : nil

    q.group 2, "[class #{full_name}#{superclass} ", "]" do
      q.breakable
      q.text "includes:"
      q.breakable
      q.seplist @includes do |inc| q.pp inc end

      q.breakable
      q.text "attributes:"
      q.breakable
      q.seplist @attributes do |inc| q.pp inc end

      q.breakable
      q.text "methods:"
      q.breakable
      q.seplist @method_list do |inc| q.pp inc end

      q.breakable
      q.text "aliases:"
      q.breakable
      q.seplist @aliases do |inc| q.pp inc end

      q.breakable
      q.text "comment:"
      q.breakable
      q.pp comment
    end
  end

end

