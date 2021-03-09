freetype_dep = dependency('freetype2')

libagg_dep = dependency('libagg', required: false)
if not libagg_dep.found()
  libagg_subproject = subproject('libagg')
  libagg_dep = libagg_subproject.get_variable('libagg_dep')
endif

font_renderer_sources = [
    'agg_font_freetype.cpp',
    'font_renderer.cpp',
]

font_renderer_cdefs = ['-DFONT_RENDERER_HEIGHT_HACK']

font_renderer_include = include_directories('.')

libfontrenderer = static_library('fontrenderer',
    font_renderer_sources,
    dependencies: [libagg_dep, freetype_dep, stb_image_dep, fmt_dep],
    cpp_args: font_renderer_cdefs,
)

