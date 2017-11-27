# frozen_string_literal: true
##
# We manage a set of attributes.  Each attribute has a symbol name and a bit
# value.

class RDoc::Markup::Attributes

  ##
  # The special attribute type.  See RDoc::Markup#add_special

  attr_reader :special

  ##
  # Creates a new attributes set.

  def initialize
    @special = 1

    @name_to_bitmap = [
      [:_SPECIAL_, @special],
    ]

    @next_bitmap = @special << 1
  end

  ##
  # Returns a unique bit for +name+

  def bitmap_for name
    bitmap = @name_to_bitmap.assoc name

    unless bitmap then
      bitmap = @next_bitmap
      @next_bitmap <<= 1
      @name_to_bitmap << [name, bitmap]
    else
      bitmap = bitmap.last
    end

    bitmap
  end

  ##
  # Returns a string representation of +bitmap+

  def as_string bitmap
    return 'none' if bitmap.zero?
    res = []

    @name_to_bitmap.each do |name, bit|
      res << name if (bitmap & bit) != 0
    end

    res.join ','
  end

  ##
  # yields each attribute name in +bitmap+

  def each_name_of bitmap
    return enum_for __method__, bitmap unless block_given?

    @name_to_bitmap.each do |name, bit|
      next if bit == @special

      yield name.to_s if (bitmap & bit) != 0
    end
  end

end

