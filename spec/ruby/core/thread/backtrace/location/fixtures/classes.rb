module ThreadBacktraceLocationSpecs
  MODULE_LOCATION = caller_locations(0) rescue nil

  def self.locations
    caller_locations
  end

  def self.method_location
    caller_locations(0)
  end

  def self.block_location
    1.times do
      return caller_locations(0)
    end
  end

  def self.locations_inside_nested_blocks
    first_level_location = nil
    second_level_location = nil
    third_level_location = nil

    1.times do
      first_level_location = locations[0]
      1.times do
        second_level_location = locations[0]
        1.times do
          third_level_location = locations[0]
        end
      end
    end

    [first_level_location, second_level_location, third_level_location]
  end
end
