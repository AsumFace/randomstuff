subdir('ocl')
subdir('cuda')

inc = include_directories('../../')

dcompute_driver_sources = [
    'backend.d',
    'error.d',
    'util.d']

dcompute_driver = library('dcompute_driver',
                          dcompute_driver_sources,
                          link_with : [dcompute_driver_ocl, dcompute_driver_cuda],
                          include_directories: inc)
