class String
  def self.greeting
    "Good evening!"
  end
end

class Integer
  class << self
    def answer
      42
    end
  end
end

class Array
  def a
    size
  end
  def self.blank
    []
  end
  def b
    size
  end
end

class Hash
  def a
    size
  end
  class << self
    def http_200
      {status: 200, body: 'OK'}
    end
  end
  def b
    size
  end
end

module SingletonMethods
  def self.string_greeing
    String.greeting
  end

  def self.integer_answer
    Integer.answer
  end

  def self.array_blank
    Array.blank
  end

  def self.hash_http_200
    Hash.http_200
  end

  def self.array_instance_methods_return_size(ary)
    [ary.a, ary.b]
  end

  def self.hash_instance_methods_return_size(hash)
    [hash.a, hash.b]
  end
end
