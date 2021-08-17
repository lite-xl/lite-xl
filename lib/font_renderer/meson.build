freetype_dep = dependency('freetype2')

if get_option('wrap_mode') == 'forcefallback'
    libagg_subproject = subproject('libagg')
    libagg_dep = libagg_subproject.get_variable('libagg_dep')
else
    libagg_dep = dependency('libagg', required: false, fallback: 'libagg')
endif

font_renderer_sources = [
    'agg_font_freetype.cpp',
    'font_renderer.cpp',
]

font_renderer_cdefs = ['-DFONT_RENDERER_HEIGHT_HACK']

font_renderer_include = include_directories('.')

libfontrenderer = static_library('fontrenderer',
    font_renderer_sources,
    dependencies: [libagg_dep, freetype_dep],
    cpp_args: font_renderer_cdefs,
)

