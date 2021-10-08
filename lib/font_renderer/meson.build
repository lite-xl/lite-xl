freetype_dep = dependency('freetype2')

libagg_dep = dependency('libagg', fallback: ['libagg', 'libagg_dep'])

font_renderer_sources = [
    'agg_font_freetype.cpp',
    'font_renderer.cpp',
]

font_renderer_cdefs = ['-DFONT_RENDERER_HEIGHT_HACK']

lite_includes += include_directories('.')

libfontrenderer = static_library('fontrenderer',
    font_renderer_sources,
    dependencies: [libagg_dep, freetype_dep],
    cpp_args: font_renderer_cdefs,
)

