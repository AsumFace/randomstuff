subdir('opencl')
subdir('cuda')
subdir('util')

inc = include_directories('..')

derelict = library('derelict',
                   link_with : [derelict_opencl, derelict_cuda, derelict_util],
                   include_directories : inc)
