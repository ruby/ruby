### Remarks

Just run it with no argument:

    ruby entry.rb

I confirmed the following implementations/platforms:

* ruby 2.5.0p0 (2017-12-25 revision 61468) [x86_64-darwin16]
* ruby 2.4.0p0 (2016-12-24 revision 57164) [x86_64-darwin16]
* ruby 2.3.1p112 (2016-04-26 revision 54768) [x86_64-darwin16]

### Description

This program will generate `wine_glass.stl`, a 3D data file(STL format) of a wine glass.
You can change the shape by modifying the DSL part.
For sake cup:
```ruby
gen3d 'ochoko.stl' do
  l------------------------l
  l-ww------------------ww-l
  l-ww------------------ww-l
  l-ww++++++++++++++++++ww-l
  l-ww++++++++++++++++++ww-l
  l--ww++++++++++++++++ww--l
  l---wwww++++++++++wwww---l
  l----wwwwwwwwwwwwwwww----l
  l----www----------www----l
end
```
`+` and `-` are the same meaning(just for apperance)
