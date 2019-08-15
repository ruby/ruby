class MSpecScript
  set :target, 'ruby'

  set :backtrace_filter, /lib\/mspec\//

  set :tags_patterns, [
                        [%r(spec/fixtures/), 'spec/fixtures/tags/'],
                        [/_spec.rb$/, '_tags.txt']
                      ]
end
