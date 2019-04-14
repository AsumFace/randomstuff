subdir('cgfm/math')
subdir('dcompute')
subdir('derelict')

inc = include_directories('.')

abb_sources = [
    'app.d',
    'rtree.d',
    'stack_container.d',
    'required.d',
    'typecons.d',
    #'sqbox.d',
    'rk.d',
    'diffkernel.d']

executable('abb',
           abb_sources,
           include_directories: inc,
           link_with : [cgfm_math, dcompute, derelict],
           objects: '/usr/lib64/clang/8.0.0/lib/linux/libclang_rt.profile-x86_64.a')
