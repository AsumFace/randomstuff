subdir('driver')
subdir('std')

inc = include_directories('..')

dcompute = library('dcompute',
                   link_with : [dcompute_driver, dcompute_std],
                   include_directories: inc)
