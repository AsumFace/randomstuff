project('abb', 'd',
        license : 'BSL-1.0')

subdir('source')

dlang = import('dlang')
dlang.generate_dub_file(meson.project_name().to_lower(),
                        meson.source_root(),
                        description: 'R-Tree data structure',
                        license: meson.project_license()[0])
