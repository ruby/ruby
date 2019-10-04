# Reserve names.
def reserve_names(*names)
  names.each  do |name|
    fail "Name #{name} is already in use" if ENV.include?(name)
  end
  @reserved_names = names
end

# Release reserved names.
def release_names
  @reserved_names.each do |name|
    ENV.delete(name)
  end
end

# Mock object for calling to_str.
def mock_to_str(s)
  mock_object = mock('name')
  mock_object.should_receive(:to_str).and_return(s.to_s)
  mock_object
end

require '../../spec_helper'
