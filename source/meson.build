subdir('cgfm/math')

inc = include_directories('.')

abb_sources = [
    'app.d',
    'rtree.d',
    'stack_container.d',
    'required.d',
    'typecons.d']

executable('abb',
           abb_sources,
           include_directories: inc,
           link_with : cgfm_math,
           objects : '/usr/lib64/clang/7.0.1/lib/linux/libclang_rt.profile-x86_64.a')
