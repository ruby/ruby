# ruby dbm acess
require "dbm"

d = DBM.open("test")
keys = d.keys
if keys.length > 0 then
  for k in keys; print k, "\n"; end
  for v in d.values; print v, "\n"; end
else
  d['foobar'] = 'FB'
  d['baz'] = 'BZ'
  d['quux'] = 'QX'
end

