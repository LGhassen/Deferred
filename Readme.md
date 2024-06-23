# Deferred - Adding deferred rendering to KSP

You'll find an [explanation of what the mod does here](https://www.patreon.com/posts/deferred-106557481).

# Dependencies

Shabby is needed (currently bundled on the github release but will be separate in future releases and CKAN).

# Mod compatibility status
In no particular order.
Mods that say "renders in forward" means they may appear to render correctly but get no deferred benefits for now (no lighting perf improvements, not compatible with any deferred ambient/lighting/effects)

| Mod  | Status | Notes |
| ------------- | ------------- |------------- |
| Textures Unlimited  |	Compatible [via fork](https://github.com/LGhassen/TexturesUnlimited/releases), otherwise renders in forward |	|
| Parallax  | Incompatible for now, tesselation has rendering issues, scatters and distant terrain render in forward |
| Conformal decals  | Incompatible for now, rendering issues, black parts due to fallback shader |
| Scatterer | Compatible |
| EVE-Redux | Compatible |
| Volumetric clouds (and related Scatterer versions) | Fixed individual DLLs [can be downloaded here for v3 and v4](https://drive.google.com/drive/folders/1lkJWJ6qfWLdJt2ZYjTYuOQk3dO7zxMCb?usp=sharing), or full updated downloads are provided on Patreon if you still have access. v1 and v2 appear to be compatible |
| TUFX | Compatible
| Shaddy | Renders in forward
| Kopernicus | Untested, same limitations to terrain shaders apply as stock (only stock Ultra terrain shaders supported for now)
| Waterfall | Compatible
| FreeIVA | Compatible
| KerbalVR | Compatible
| SimpleAdjustableFairings  | Compatible but transparency doesn't work in editors
| KerbalKonstructs | Mix of rendering in forward and visual issues, fix submitted by me to KK maintainers and awaiting approval
| NeptuneCamera  | Incompatible
| RasterPropMonitor | Unknown/untested
| Camera mods | Unknown/untested
| Engine Lighting | Unknown/untested

# Debug menu
Using alt + d ( right shift + d on linux) will bring up a simple debug menu cycling between the contents of the g-buffer (albedo, normals, smoothness, specularColor, occlusion) and a composite of the emission+calculated ambient

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

