# Deferred - Adding deferred rendering to KSP

You'll find an [explanation of what the mod does here](https://www.patreon.com/posts/deferred-106557481).

# Dependencies

Shabby is needed (currently bundled on the github release but will be separate in future releases and CKAN).

# Limitations/known issues
## Terrain shaders
Only "Ultra" quality terrain shaders are compatible, that includes both atlas and non-atlas terrain shaders. Terrain quality is forced to Ultra when the mod loads.

Names of compatible terrain shaders:

 - PQSTriplanarZoomRotation.shader
 - PQSTriplanarZoomRotationTextureArray - 1Blend.shader
 - PQSTriplanarZoomRotationTextureArray - 2Blend.shader
 - PQSTriplanarZoomRotationTextureArray - 3Blend.shader
 - PQSTriplanarZoomRotationTextureArray - 4Blend.shader

## Transparency
Traditional transparency doesn't work in deferred rendering for opaque objects (only used in the editors in KSP). To emulate transparency, a stylized dissolve effect (left on the below image) is used on fairing-only shaders.

A dithering effect (right on the below image) can be applied on regular shaders but is disabled by default because it is distracting (you'll find an option in the settings file).

![enter image description here](https://i.imgur.com/RIjNtSZ.png)

# Mod compatibility status
In no particular order.
Mods that say "renders in forward" means they may appear to render correctly but get no deferred benefits for now (no lighting perf improvements, not compatible with any deferred ambient/lighting/effects)

| Mod  | Status | Notes |
| ------------- | ------------- |------------- |
| Textures Unlimited  |	Compatible [via fork](https://github.com/LGhassen/TexturesUnlimited/releases), otherwise renders in forward |	|
| Parallax  | Compatible (you need the latest version) |
| Conformal decals  | Renders in forward |
| Scatterer | Compatible |
| EVE-Redux | Compatible |
| Volumetric clouds (and related Scatterer versions) | Fixed individual DLLs [can be downloaded here for v3 and v4](https://drive.google.com/drive/folders/1lkJWJ6qfWLdJt2ZYjTYuOQk3dO7zxMCb?usp=sharing), or full updated downloads are provided on Patreon if you still have access. v1 and v2 appear to be compatible |
| TUFX | Compatible
| Shaddy | Renders in forward
| Kopernicus | Mostly compatible, some planet packs have issues with the terrain shader of the homeworld, or with some of the below-ultra unsupported terrain shaders
| Waterfall | Compatible
| FreeIVA | Compatible
| KerbalVR | Compatible
| PlanetShine | Compatible, but obsolete at default settings. Use if you have custom settings, want more control over lighting and know what you are doing
| SimpleAdjustableFairings  | Compatible
| KerbalKonstructs | Compatible
| RasterPropMonitor | Compatible
| Engine Lighting | Compatible
| B9 Procedural Wings | Compatible [via fork](https://github.com/LGhassen/B9-PWings-Modified/releases) (awaiting merge), otherwise renders in forward
| Kronal Vessel Viewer | Compatible
| KSRSS  | Compatible in 1.1.9, local space terrain may be a bit shinier or less shiny than original
| NeptuneCamera  | Incompatible
| Camera mods | Unknown/untested

# Debug menu
Using alt + d ( right shift + d on linux) will bring up a simple debug menu cycling between the contents of the g-buffer (albedo, normals, smoothness, specularColor, occlusion) and a composite of the emission+calculated ambient

Transparencies and incompatible forward shaders will render on top of the debug visualization, ignoring the g-buffer mode selected. This can also be used to identify incompatible/forward shaders (ignoring transparencies)

![enter image description here](https://i.imgur.com/ZgSDZnu.jpeg)

# Stencil buffer usage
Only 3 bits of the stencil buffer appear to be available in deferred rendering because the rest are used internally by Unity.
This is undocumented for version 2019.4 of Unity but the available bits appear to be bits 0, 1, and 5, which correspond to values 1, 2, and 32. Because this is undocumented this usage could turn out to be wrong and bugs may be discovered in the future. Later versions of the documentation say that only bit 5 is actually available, this may not be true for 2019.4 and seems to work in KSP.

Stencil buffer is useful for applying post effects selectively to certain surfaces, we can take advantage of it here since we are using new shaders and can implement stencil everywhere. I propose the following stencil values be used for masking, they are already used by this mod for replaced shaders:

| Surface/Shader type | Stencil value | Notes |
| ------------- | ------------- |------------- |
| Parts  | 1|	|
| Terrain (stock/parallax)  | 2 | Already used in this mod to emulate the PQS's alpha fade to scaled, since it is impossible to do alpha blending otherwise in deferred (dithering looked really bad here and caused other issues with visual mods)|
| Local scenery (buildings + stock/parallax scatters)  | 3|
| Parallax grass | 32  | Parallax grass has normals that point upwards, matching the terrain and not the grass itself so it might be worthwhile to have a separate stencil value for it, for any image effects that might need accurate normals|
## Writing stencil values

To write stencil values from a shader, add a stencil block with the stencil value to write, e.g for parts:

        Tags { "RenderType"="Opaque" }

        Stencil
        {
            Ref 1
            Comp Always
            Pass Replace
        }  

        CGPROGRAM
        ...

## Testing stencil values

For testing/checking stencil values in a post effect, multiple approaches can be used as seen in https://docs.unity3d.com/Manual/SL-Stencil.html

Here are examples to check for the surfaces above or combinations of them


### Checking for parts only
Check only for value 1

            Stencil
            {
                Ref 1
                Comp Equal
                ReadMask 35
                Pass Keep
            }

### Checking for PQS only
Check only for value 2

            Stencil
            {
                Ref 2
                Comp Equal
                ReadMask 35
                Pass Keep
            }
### Checking for Scenery only
Check only for value 3

            Stencil
            {
                Ref 3
                Comp Equal
                ReadMask 35
                Pass Keep
            }
### Checking for Parallax grass only
Check only for value 32

            Stencil
            {
                Ref 32
                Comp Equal
                ReadMask 35
                Pass Keep
            }

### Checking for PQS or scenery but not grass
Check for values less or equal to 3 greater than 1

            Stencil
            {
                Ref 1
                Comp Less
                ReadMask 3
                Pass Keep
            }
### Checking for PQS or scenery or grass
Check for values less or equal to 35 greater than 1

            Stencil
            {
                Ref 1
                Comp Less
                ReadMask 35
                Pass Keep
            }
### Checking for grass or scenery but not PQS
Check for values less or equal to 35 greater than 2

            Stencil
            {
                Ref 2
                Comp Less
                ReadMask 35
                Pass Keep
            }
