module A a = 1 end

%Q{aaa #{bbb} ccc}

module m::M
end

module A
 x = 1; rescue; end

module ::A
end

module A[]::B
end

module A[1]::B
end
