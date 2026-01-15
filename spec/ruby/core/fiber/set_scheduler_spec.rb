require_relative '../../spec_helper'
require_relative 'shared/scheduler'

require "fiber"

describe "Fiber.scheduler" do
  it_behaves_like :scheduler, :set_scheduler
end
