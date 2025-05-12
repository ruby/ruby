module StringExt
  FOO = "foo 1"
  def say_foo
    "I'm saying " + FOO
  end
end

class String
  include StringExt
  def say
    say_foo
  end
end

module OpenClassWithInclude
  def self.say
    String.new.say
  end

  def self.say_foo
    String.new.say_foo
  end

  def self.say_with_obj(str)
    str.say
  end

  def self.refer_foo
    String::FOO
  end
end
