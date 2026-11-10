# frozen_string_literal: true

module VendoredCompactIndex
  Gem = Struct.new(:name, :versions) do
    def <=>(other)
      name <=> other.name
    end
  end
end
