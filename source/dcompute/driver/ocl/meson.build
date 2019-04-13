subdir('raw')

dcompute_driver_ocl_sources = [
    'buffer.d',
    'context.d',
    'device.d',
    'event.d',
    'image.d',
    'kernel.d',
    'memory.d',
    'meson.build',
    'package.d',
    'platform.d',
    'program.d',
    'queue.d',
    'sampler.d',
    'util.d']

dcompute_driver_ocl = library('dcompute_driver_ocl',
                              dcompute_driver_ocl_sources
                              link_with : dcompute_driver_ocl_raw)
