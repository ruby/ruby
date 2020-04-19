require "minitest/autorun"

module Kaigi
  class Conference
    attr_reader :talks

    def initialize
      @talks = []
    end

    def speakers
      talks.flat_map(&:speakers)
    end

    def each_speaker(&block)
      speakers.each(&block)
      self
    end
  end

  class Talk
    attr_reader :title
    attr_reader :speakers

    def initialize(title:)
      @title = title
      @speakers = []
    end
  end

  class Speaker
    attr_reader :name
    attr_reader :email

    def initialize(name:, email:)
      @name = name
      @email = email
    end
  end
end

class Kaigi::ConferenceTest < Minitest::Test
  def test_1
    conference = Kaigi::Conference.new

    talk = Kaigi::Talk.new(title: "An introduction to typed Ruby programming")
    talk.speakers << Kaigi::Speaker.new(name: "Soutaro Matsumoto", email: :"matsumoto@soutaro.com")

    conference.talks << talk

    conference.speakers {}

    assert_equal ["Soutaro Matsumoto"], conference.speakers.map(&:name)
  end
end
