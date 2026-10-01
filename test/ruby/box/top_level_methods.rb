def top_level_private; end
private :top_level_private

def top_level_public; end
public :top_level_public

module TopLevelInclude; end
include TopLevelInclude

define_method(:top_level_defined) { :ok }

ruby2_keywords def top_level_ruby2_keywords(*args); args; end

module TopLevelRefinement
  refine(String) { def top_level_refined; end }
end
using TopLevelRefinement
