# PyInstaller spec for maestro-tui
block_cipher = None

from PyInstaller.utils.hooks import collect_submodules

hiddenimports = collect_submodules('textual') + collect_submodules('rich')

a = Analysis(['-m', 'maestro_tui.app'],
             pathex=['src'],
             binaries=[],
             datas=[],
             hiddenimports=hiddenimports,
             hookspath=[],
             runtime_hooks=[],
             excludes=[],
             noarchive=False)
pyz = PYZ(a.pure, a.zipped_data,
             cipher=block_cipher)
exe = EXE(pyz,
          a.scripts,
          [],
          exclude_binaries=True,
          name='maestro-tui',
          debug=False,
          bootloader_ignore_signals=False,
          strip=False,
          upx=True,
          console=True)
coll = COLLECT(exe,
               a.binaries,
               a.zipfiles,
               a.datas,
               strip=False,
               upx=True,
               upx_exclude=[],
               name='maestro-tui')

