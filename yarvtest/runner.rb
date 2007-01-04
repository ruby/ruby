require 'test/unit'

if $0 == __FILE__
  # exit Test::Unit::AutoRunner.run(false, File.dirname($0))
  Dir.glob(File.dirname($0) + '/test_*'){|file|
    require file
  }
end

