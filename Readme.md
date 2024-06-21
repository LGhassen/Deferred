# Deferred - Adding deferred rendering to KSP

This mod adds deferred rendering support to KSP.

Deferred rendering decouples geometry rendering from lighting, allowing for more modern lighting techniques to be used in the future, and better lighting performance with many light sources.

A lot of the game's shaders are replaced with entirely new ones to make this work.
Please read the mod compatibility list, current benefits and limitations sections.

# Dependencies

Shabby is needed (bundled on the github release but not on SpaceDock).

# Current benefits
## Better ambient lighting
Ambient is now applied to the scene using the stock reflection probe. This is something that TexturesUnlimited already did but only for parts, this is now applied for everything in the scene including terrain, buildings etc.

Left: Stock. Right: New lighting

![enter image description here](https://i.imgur.com/QfqYE0I.jpeg)
![enter image description here](https://i.imgur.com/wP9Q1ki.jpeg)
![enter image description here](https://i.imgur.com/JMdb0Rb.jpeg)
![enter image description here](https://i.imgur.com/L6bgRLP.jpeg)
![enter image description here](https://i.imgur.com/8O28pBM.png)

## Lighting performance
One of the main advantages of deferred rendering is eliminating the prohibitive cost of using many pixels lights, as seen in the below video (click):

[![Pixel lights performance](https://i.imgur.com/s8pN5Nq.png)](https://www.youtube.com/watch?v=Qn9h8GK7cY4)

# Known issues
## Terrain shader support
As stock shaders are incompatible with deferred rendering, the terrain shaders are replaced with entirely new ones implemented from scratch to approximate the functionality of the stock ones. For now only the "Ultra" setting terrain shaders are replaced, meaning other settings won't work. That includes the regular, non-atlas ultra shader used on all the bodies (outside of Kerbin) to be clear (PQSTriplanarZoomRotation).
As these are new shaders you might notice increased tiling in some areas, and slightly different colors.
**Examples**
Mistmach between runway grass and terrain color
![enter image description here](https://i.imgur.com/G6HgUnT.png)Some visible grass tiling
![enter image description here](https://i.imgur.com/ajA9uZF.png)

## Altered visual appearance
Some parts may look shinier or different than stock, although I tried to keep them looking reasonable.
## Ambient looking flat at noon
Ambient may look a little flat at noon, as seen here:
![enter image description here](https://i.imgur.com/tXQZlBv.png)

# Mod compatibility status
In no particular order.
Mods that say "renders in forward" means they may appear to render correctly but get no deferred benefits for now (no lighting perf improvements, not compatible with any deferred ambient/lighting/effects)

| Mod  | Status | Notes |
| ------------- | ------------- |------------- |
| Textures Unlimited  |	Compatible [via fork](https://github.com/LGhassen/TexturesUnlimited/releases), otherwise renders in forward |	|
| Parallax  | Incompatible for now, tesselation has rendering issues, scatters and distant terrain render in forward |
| Conformal decals  | Incompatible for now, rendering issues, black parts due to fallback shader |
| Scatterer | Compatible on Windows, OpenGL/Linux/Mac need to use [this fixed version](https://github.com/LGhassen/Scatterer/releases/tag/839) |
| EVE-Redux | Compatible |
| Volumetric clouds (and related Scatterer versions) | Fixed individual DLLs [can be downloaded here for v3 and v4](https://drive.google.com/drive/folders/1lkJWJ6qfWLdJt2ZYjTYuOQk3dO7zxMCb?usp=sharing), or full updated downloads are provided on Patreon if you still have access. v1 and v2 appear to be compatible |
| TUFX | Compatible
| Shaddy | Renders in forward
| Kopernicus | Untested, same limitations to terrain shaders apply as stock (only stock Ultra terrain shaders supported for now)
| RasterPropMonitor | Unknown/untested
| Camera mods | Unknown/untested
| Waterfall | Compatible
| Engine Lighting | Unknown/untested

# Debug menu
Using alt+d will bring up a simple debug menu cycling between the contents of the g-buffer (albedo, normals, smoothness, specularColor, occlusion) and a composite of the emission+calculated ambient

Transparencies and incompatible forward shaders will render on top of the debug visualization, ignoring the g-buffer mode selected. This can also be used to identify incompatible/forward shaders (ignoring transparencies)

![enter image description here](https://i.imgur.com/ZgSDZnu.jpeg)

# Stencil buffer usage
Only 4 bits of the stencil buffer appear to be available in deferred rendering because reasons.
Stencil buffer is useful for applying post effects selectively to certain surfaces, we can take advantage of it here since we are using new shaders and can implement stencil everywhere. I propose the following stencil values be used for masking, they are already used by this mod for replaced shaders:

| Surface/Shader type | Stencil bit| Stencil value | Notes |
| ------------- | ------------- |------------- |------------- |
| Terrain (stock/parallax)  | 0	| 1 | Already used in this mod to emulate the alpha PQS to scaled fade, since it is impossible to do alpha blending otherwise in deferred (dithering looked really bad here and caused other issues with visual mods)|
| Parallax grass | 1 |	2 | Parallax grass has normals that point upwards, matching the terrain and not the grass itself so it might be worthwhile to have a separate stencil value for it, for any image effects that might need accurate normals|
| Local scenery (buildings + stock/parallax scatters)  | 2|	4 | |
| Parts  | 3|	8 | |
## Writing stencil values

To write stencil values from a shader, add a stencil block with the stencil value to write, e.g for parts:

        Tags { "RenderType"="Opaque" }

        Stencil
        {
            Ref 8
            Comp Always
            Pass Replace
        }  

        CGPROGRAM
        ...

## Testing stencil values

For testing/checking stencil values in a post effect, combine the stencil bits you want to test for, use that as ReadMask and verify that the result is superior to zero, using Comp and Ref as seen in https://docs.unity3d.com/Manual/SL-Stencil.html
Examples:
To check for Parts:

            Stencil
            {
                ReadMask 8
                Comp Greater
                Ref 0
                Pass Keep
            }

To check for Scenery and terrain, combine bits 2 and 0:

            Stencil
            {
                ReadMask 5
                Comp Greater
                Ref 0
                Pass Keep
            }

To check for terrain and only terrain

            Stencil
            {
                ReadMask 1
                Comp Equal
                Ref 1
                Pass Keep
            }
