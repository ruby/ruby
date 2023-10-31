false ? raise do end : tap do end

false ? raise {} : tap {}

true ? 1.tap do |n| p n end : 0
