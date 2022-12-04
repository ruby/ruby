class MSpecScript
  set :target, 'ruby'

  set :tags_patterns, [
                        [%r(spec/fixtures/), 'spec/fixtures/tags/'],
                        [/_spec.rb$/, '_tags.txt']
                      ]
end
