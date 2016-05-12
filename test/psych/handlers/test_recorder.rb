# frozen_string_literal: false
require 'psych/helper'
require 'psych/handlers/recorder'

module Psych
  module Handlers
    class TestRecorder < TestCase
      def test_replay
        yaml   = "--- foo\n...\n"
        output = StringIO.new

        recorder = Psych::Handlers::Recorder.new
        parser   = Psych::Parser.new recorder
        parser.parse yaml

        assert_equal 5, recorder.events.length

        emitter = Psych::Emitter.new output
        recorder.events.each do |m, args|
          emitter.send m, *args
        end
        assert_equal yaml, output.string
      end
    end
  end
end
