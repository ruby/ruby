#
# Profiles are SimpleCov configuration procs that can be easily
# loaded using SimpleCov.start :rails and defined using
#   SimpleCov.profiles.define :foo do
#     # SimpleCov configuration here, same as in  SimpleCov.configure
#   end
#
class SimpleCov::Profiles < Hash
  #
  # Define a SimpleCov profile:
  #   SimpleCov.profiles.define 'rails' do
  #     # Same as SimpleCov.configure do .. here
  #   end
  #
  def define(name, &blk)
    name = name.to_sym
    raise "SimpleCov Profile '#{name}' is already defined" unless self[name].nil?
    self[name] = blk
  end

  #
  # Applies the profile of given name on SimpleCov.configure
  #
  def load(name)
    name = name.to_sym
    raise "Could not find SimpleCov Profile called '#{name}'" unless has_key?(name)
    SimpleCov.configure(&self[name])
  end
end
