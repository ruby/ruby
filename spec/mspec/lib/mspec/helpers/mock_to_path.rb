def mock_to_path(path)
  # Cannot use our Object#mock here since it conflicts with RSpec
  obj = MockObject.new('path')
  obj.should_receive(:to_path).and_return(path)
  obj
end
