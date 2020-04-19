require_relative "test_helper"

class BindingTest < StdlibTest
  target Binding
  using hook.refinement

  def test_eval
    binding.eval('1', '(eval)', 1)
  end

  def test_local_variable_defined?
    binding.local_variable_defined?(:yes)
    yes = true
    binding.local_variable_defined?('yes')
  end

  def test_local_variable_get
    foo = 1
    binding.local_variable_get(:foo)
    binding.local_variable_get('foo')
  end

  def test_local_variable_set
    binding.local_variable_set(:foo, 1)
    binding.local_variable_set('foo', 1)
  end

  def test_local_variables
    foo = 1
    binding.local_variables
  end

  def test_source_location
    binding.source_location
  end
end
