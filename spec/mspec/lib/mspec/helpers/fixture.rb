# Returns the name of a fixture file by adjoining the directory
# of the +file+ argument with "fixtures" and the contents of the
# +args+ array. For example,
#
#   +file+ == "some/example_spec.rb"
#
# and
#
#   +args+ == ["subdir", "file.txt"]
#
# then the result is the expanded path of
#
#   "some/fixtures/subdir/file.txt".
def fixture(file, *args)
  path = File.dirname(file)
  path = path[0..-7] if path[-7..-1] == "/shared"
  fixtures = path[-9..-1] == "/fixtures" ? "" : "fixtures"
  if File.respond_to?(:realpath)
    path = File.realpath(path)
  else
    path = File.expand_path(path)
  end
  File.join(path, fixtures, args)
end
