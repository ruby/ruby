##
# A set which represents the installed gems. Respects
# all the normal settings that control where to look
# for installed gems.

class Gem::DependencyResolver::CurrentSet

  def find_all req
    req.dependency.matching_specs
  end

  def prefetch gems
  end

end

