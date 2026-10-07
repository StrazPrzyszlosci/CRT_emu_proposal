RetroCRT Soft Auto - RetroArch Slang shader

Files
-----
retrocrt_soft.slang
    Pass 0: soft CRT blur + scanlines + contrast/brightness.

retrocrt_finish.slang
    Pass 1: horizontal softness + detail + unsharp + softening/smoothing.

retrocrt_tone.slang
    Pass 2: automatic local tone preservation against RetroArch Original.

retrocrt_soft_auto.slangp
    Ready-to-load 3-pass preset.

Installation
------------
Copy all four files into the same folder inside your RetroArch shaders directory.
Then in RetroArch choose:
Settings -> Video -> Shaders -> Load Shader Preset
and select retrocrt_soft_auto.slangp.

Notes
-----
This is a shader-native port of the supplied WebGL pipeline. The WebGL code uses
CPU-side full-frame histogram-style processing; RetroArch Slang shaders are
per-pixel and do not have the same convenient full-frame reduction step. The final
pass therefore uses automatic local tone/contrast matching against Original,
which preserves source black/mid/highlight behavior without requiring a costly
full-frame histogram pass.

Main starting values intentionally remain close to the supplied renderer:
blur 7, scanline strength 0.65, frequency 120, contrast 1.2, detail 0.5,
unsharp 0.8, and final smoothing.
