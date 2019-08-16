project('behold', 'd')

behold_sources = [
  'source/sedectree.d',
  'source/cgfm/math/box.d',
  'source/cgfm/math/funcs.d',
  'source/cgfm/math/matrix.d',
  'source/cgfm/math/package.d',
  'source/cgfm/math/quaternion.d',
  'source/cgfm/math/shapes.d',
  'source/cgfm/math/simplerng.d',
  'source/cgfm/math/vector.d',
  'source/main.d',
  'source/word.d',
  'source/zstdc.d'
]

inc_dirs = [
    'source/',
    'subprojects/bindbc-glfw/source',
    'subprojects/bindbc-loader/source',
    'subprojects/bindbc-opengl/source',
    'subprojects/bindbc-freetype/source'
]

ed_versions = [
    'BindGLFW_Static',
    'GL_45',
    'GL_ARB',
    'BindFT_Static',
    'FT_29',
    'bindbc',
   # 'GL_AllowDeprecated',
    'useKHRDebug',
    'X11'
]


arsd_proj = subproject('arsd', default_options : ['bindbc=true', 'ud_versions=@0@'.format(ed_versions)])
arsd_dep = arsd_proj.get_variable('arsd_dep')
bindbc_glfw_proj = subproject('bindbc-glfw', default_options : 'ud_versions=@0@'.format(ed_versions))
bindbc_glfw_dep = bindbc_glfw_proj.get_variable('bindbc_glfw_dep')
bindbc_opengl_proj = subproject('bindbc-opengl', default_options : 'ud_versions=@0@'.format(ed_versions))
bindbc_opengl_dep = bindbc_opengl_proj.get_variable('bindbc_opengl_dep')


glfw_dep = dependency('glfw3', version : '>=3.0.0')
freetype_dep = dependency('freetype2', version : '>=2.7')
gl_dep = dependency('gl')
fontconfig_dep = dependency('fontconfig')
x11_dep = dependency('x11')
xext_dep = dependency('xext')
zstd_dep = dependency('libzstd', static : true)

executable('behold',
    behold_sources,
    include_directories : inc_dirs,
    d_module_versions : ed_versions,
    dependencies : [arsd_dep, glfw_dep, freetype_dep, gl_dep, fontconfig_dep, x11_dep, xext_dep, zstd_dep],
    link_with : [arsd_proj.get_variable('arsd_lib'),
         bindbc_glfw_proj.get_variable('bindbc_glfw_lib'),
         bindbc_opengl_proj.get_variable('bindbc_opengl_lib')])
