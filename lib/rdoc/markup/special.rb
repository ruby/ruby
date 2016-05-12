# frozen_string_literal: false
##
# Hold details of a special sequence

class RDoc::Markup::Special

  ##
  # Special type

  attr_reader   :type

  ##
  # Special text

  attr_accessor :text

  ##
  # Creates a new special sequence of +type+ with +text+

  def initialize(type, text)
    @type, @text = type, text
  end

  ##
  # Specials are equal when the have the same text and type

  def ==(o)
    self.text == o.text && self.type == o.type
  end

  def inspect # :nodoc:
    "#<RDoc::Markup::Special:0x%x @type=%p, @text=%p>" % [
      object_id, @type, text.dump]
  end

  def to_s # :nodoc:
    "Special: type=#{type} text=#{text.dump}"
  end

end

