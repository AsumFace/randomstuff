subdir('opencl')
subdir('cuda')

inc = include_directories('../..')

dcompute_std_sources = [
    'atomic.d',
    'floating.d',
    'index.d',
    'integer.d',
    'memory.d',
    'package.d',
    'pack.d',
    'sync.d',
    'warp.d']

dcompute_std = library('dcompute_std',
                       dcompute_std_sources,
                       # link_with : [dcompute_std_opencl, dcompute_std_cuda],
                       include_directories: inc)
