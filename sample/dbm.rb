# ruby
#

d = DBM.open("test")
for k in d.keys; print(k, "\n"); end
for v in d.values; print(v, "\n"); end
