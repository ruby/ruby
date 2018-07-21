                                                    X=[];def self.method_missing n;n.to_s.chars;end
                                               l=[];def l.-a;X<<a=[nil,*a];a;end;def l.+a;self-a;end
                                           class Array;def-@;[]-self;end;def-a;replace [*self,nil,*a
                                 ]end;alias +@ -@;alias + -;end;def gen3d f;yield;b=['solid obj'];w,
                 h=X[0].size,X.size;X<<[];a=->r,z,dr,dz{;r-=w/2.0;z*=2;r2,z2=r+dr,z+dz*2;if r>0||r2>
                 0;r=[0,r].max;r2=[0,r2].max;16.times{|i|m=Math;p=m::PI/8;;c,s=m.cos(t=i*p),m.sin(t)
                 c2,s2=m.cos(t=(i+1)*p),m.sin(t);t-=p/2;[[0,1,2],[0,2,3]].map{|a|b.push [:facet,'n'+
               +                 'ormal',dz*m.cos(t),dz*m.sin(t),-dr]*' ','outer loop',a.map{|i|'v'+
              ++                           "ertex #{[[r*c,r*s,z],[r*c2,r*s2,z],[r2*c2,r2*s2,z2],[r2*
              +c,                              r2*s,z2]][i]*' '}"},:endloop,:endfacet}}end};(0...h).
             map{|                                  y|w.times{|x|[X[y-1][x]||a[x,y,1,0],X[y+1][x]||
           a[x+1,y+
          1,-1,0],X[
         y][x-+1]||a[
        x,y+1,0,-1],X[y
       ][x++1]||a[x+1,y,
       0,1]]if X[y][x]}}
       s=[b,'end'+b[0]]*
        $/;File.write(f,
         s);X.replace(
            []);end

gen3d 'wine_glass.stl' do
  l--ww------------------ww--l
  l--ww------------------ww--l
  l--ww++++++++++++++++++ww--l
  l--ww++++++++++++++++++ww--l
  l--ww++++++++++++++++++ww--l
  l--ww++++++++++++++++++ww--l
  l---ww++++++++++++++++ww---l
  l----www++++++++++++www----l
  l------www++++++++www------l
  l--------wwwwwwwwww--------l
  l-----------wwww-----------l
  l------------ww------------l
  l------------ww------------l
  l------------ww------------l
  l-----------wwww-----------l
  l---------wwwwwwww---------l
  l----wwwwwwwwwwwwwwwwww----l
end
