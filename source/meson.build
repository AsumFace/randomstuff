
if get_option('dcompute')
    add_project_arguments('-d-version=dcompute', language : 'd')
    abb_dcompute_sources = 'diffkernel.d'

    dcompute_proj = subproject('dcompute')
    dcompute_dep = dcompute_proj.get_variable('dcompute_dep')
else
    abb_dcompute_sources = []
    dcompute_dep = []
endif

subdir('cgfm/math')

inc = include_directories('.')

abb_sources = [
    'app.d',
    'rtree.d',
    'stack_container.d',
    'required.d',
    'typecons.d',
    #'sqbox.d',
    'rk.d',
    'polygon.d',
    'xxhash.d',
    abb_dcompute_sources]

executable('abb',
           abb_sources,
           include_directories: inc,
           link_with : cgfm_math,
           objects: '/usr/lib64/clang/8.0.0/lib/linux/libclang_rt.profile-x86_64.a',
           dependencies : dcompute_dep)
