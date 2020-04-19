require_relative "test_helper"

require "erb"

class ERBTest < StdlibTest
  target ERB
  library "erb"

  using hook.refinement

  def test_version
    ERB.version
  end

  def test_initialize
    ERB.new(template)
    ERB.new(template, eoutvar: '_erb')
    ERB.new(template, trim_mode: nil)
    ERB.new(template, trim_mode: 1)
    ERB.new(template, trim_mode: '%')
    ERB.new(template, trim_mode: '%', eoutvar: '_erb')
  end

  def test_src
    ERB.new(template).src
  end

  def test_encoding
    ERB.new(template).encoding
  end

  def test_filename
    erb = ERB.new(template)
    erb.filename
    erb.filename = nil
    erb.filename
    erb.filename = '(eval)'
    erb.filename
  end

  def test_lineno
    erb = ERB.new(template)
    erb.lineno
    erb.lineno = 100
    erb.lineno
  end

  def test_location
    erb = ERB.new(template)
    erb.location = ['(eval)', 100]
  end

  def test_run
    erb = ERB.new('')
    erb.run
    erb.run(binding)
  end

  def test_result
    erb = ERB.new(template)
    erb.result
    erb.result(binding)
  end

  def test_result_with_hash
    erb = ERB.new(template)
    erb.result_with_hash({})
    erb.result_with_hash({ 'foo' => 'bar' })
  end

  def test_def_method
    erb = ERB.new(template)
    erb.def_method(Module.new, 'erb')
    erb.def_method(Module.new, 'erb', 'ERB')
  end

  def test_def_module
    erb = ERB.new(template)
    erb.def_module
    erb.def_module('erb')
  end

  def test_def_class
    erb = ERB.new(template)
    erb.def_class
    erb.def_class(Object)
    erb.def_class(Object, 'erb')
  end

  private

  def template
    '<%= ERB.version %>'
  end
end
