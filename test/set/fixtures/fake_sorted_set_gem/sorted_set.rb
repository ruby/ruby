Object.instance_exec do
  # Remove the constant to cancel autoload that would be fired by
  # `class SortedSet` and cause circular require.
  remove_const :SortedSet if const_defined?(:SortedSet)
end

class SortedSet < Set
  # ...
end
