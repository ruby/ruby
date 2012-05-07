require 'ostruct'

module JSON
  class GenericObject < OpenStruct
    class << self
      alias [] new

      def json_create(data)
        data = data.dup
        data.delete JSON.create_id
        self[data]
      end
    end

    def to_hash
      table
    end

    def [](name)
      table[name.to_sym]
    end

    def []=(name, value)
      __send__ "#{name}=", value
    end

    def |(other)
      self.class[other.to_hash.merge(to_hash)]
    end

    def as_json(*)
      { JSON.create_id => self.class.name }.merge to_hash
    end

    def to_json(*a)
      as_json.to_json(*a)
    end
  end
end
