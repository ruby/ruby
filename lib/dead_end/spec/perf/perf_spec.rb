# frozen_string_literal: true

require_relative "../spec_helper.rb"
require "benchmark"

module DeadEnd
  RSpec.describe "perf" do
    it "doesnt timeout" do
      source = fixtures_dir.join("routes.txt.rb").read

      io = StringIO.new
      bench = Benchmark.measure do
        DeadEnd.call(
          io: io,
          source: source,
          filename: "none",
        )
      end

      expect(io.string).to include(<<~'EOM'.indent(4))
           1  Rails.application.routes.draw do
          107    constraints -> { Rails.application.config.non_production } do
          111    end
        ❯ 113    namespace :admin do
        ❯ 116    match "/foobar(*path)", via: :all, to: redirect { |_params, req|
        ❯ 120    }
          121  end
      EOM

      expect(bench.real).to be < 1 # second
    end
  end
end
