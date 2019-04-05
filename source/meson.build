subdir('cgfm/math')

inc = include_directories('.')

abb_sources = [
    'app.d',
    'rtree.d',
    'stack.d',
    'required.d']

executable('abb',
           abb_sources,
           include_directories: inc,
           link_with : cgfm_math)
