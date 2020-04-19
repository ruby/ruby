require_relative "test_helper"

class ModuleTest < StdlibTest
  target Module
  using hook.refinement

  def test_used_modules
    Module.used_modules
  end
end
