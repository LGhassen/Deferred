
# Deferred - Adding deferred rendering to KSP

You'll find an [explanation of what the mod does here](https://www.patreon.com/posts/deferred-106557481).
# Install instructions
## Automatic installation
Get [CKAN](https://github.com/KSP-CKAN/CKAN/releases) and use it to install Deferred. CKAN is recommended because it automatically handles dependencies and mod conflicts.

## Manual installation
Go to [releases](https://github.com/LGhassen/Deferred/releases) and grab the latest .zip. Unzip it, merge the provided GameData folder with your game's GameData folder (typically **C:\Program Files\Steam\SteamApps\common\Kerbal Space Program\GameData**).

Get the latest version of [Shabby](https://archive.org/search?query=creator:%22taniwha%22%20shabby) and install it in the same way.

Get the latest version of [HarmonyKSP](https://github.com/KSPModdingLibs/HarmonyKSP) and install it in the same way.

You should see the following folder structure:

```
Kerbal Space program
└──────GameData
		├──────000_Harmony
		├──────Shabby
		└──────zzz_Deferred
```

Make sure you downloaded the release linked above and not the code, if you see Deferred-Master you messed up and downloaded the code.

Check the mod compatibility list below and update mods as needed.

# Reporting issues

To report an issue add screenshots of the issue, reproduction steps and your KSP.log file, otherwise your report may not be taken into account.

# Limitations/known issues

## Transparency
Traditional transparency doesn't work in deferred rendering for opaque objects (only used in the editors in KSP). To emulate transparency, a stylized dissolve effect (left on the below image) is used on fairing-only shaders.

A dithering effect (right on the below image) can be applied on regular shaders but is disabled by default because it is distracting (you'll find an option in the settings file).

![enter image description here](https://i.imgur.com/RIjNtSZ.png)

# Mod compatibility status
In no particular order.
Mods that say "renders in forward" means they may appear to render correctly but get no deferred benefits for now (no lighting perf improvements, not compatible with any deferred ambient/lighting/effects)

| Mod  | Status | Notes |
| ------------- | ------------- |------------- |
| Textures Unlimited  |	Compatible since version 1.6.0.26 on CKAN or [github](https://github.com/KSPModStewards/TexturesUnlimited/releases) |	|
| Parallax  | Compatible since version 2.0.8 |
| Conformal decals  | Renders in forward in 0.2.14, older versions incompatible |
| B9 Procedural Wings | Compatible since version 0.46.0
| Scatterer | Compatible |
| EVE-Redux | Compatible |
| Volumetric clouds (and related Scatterer versions) | Fixed individual DLLs [can be downloaded here for v3 and v4](https://drive.google.com/drive/folders/1lkJWJ6qfWLdJt2ZYjTYuOQk3dO7zxMCb?usp=sharing), or full updated downloads are provided on Patreon if you still have access. v1 and v2 appear to be compatible |
| TUFX | Compatible
| Kopernicus | Compatible
| Waterfall | Compatible
| KerbalVR | Compatible
| SimpleAdjustableFairings  | Compatible
| KerbalKonstructs | Compatible
| Engine Lighting | Compatible
| Kronal Vessel Viewer | Compatible
| KSRSS  | Compatible 
| RSS  | Compatible
| PlanetShine | Compatible, but obsolete at default settings. Use if you have custom settings, want more control over lighting and know what you are doing
| RasterPropMonitor | Compatible since version 1.0.1
| ASET IVA Props and related mods | Compatible, use the latest official version of RPM, otherwise black outline around labels
| Magpie Mods | If you must use it, get latest compatible TU version then [replace deprecated shaders in configs](https://forum.kerbalspaceprogram.com/topic/192310-magpie-mods/?do=findComment&comment=4410772)
| FreeIVA | Fully compatible since version 0.2.19.0, versions before that have other parts of the craft appear hollow when seen through windows
| Shaddy | Renders in forward
| NeptuneCamera  | Incompatible
| ProceduralFairings | Incompatible, white fairings on hover
| Camera mods | Unknown/untested


# Debug menu
Using control + d (keys configurable) will bring up a simple debug menu cycling between the contents of the g-buffer (albedo, normals, smoothness, specularColor, occlusion) and a composite of the emission+calculated ambient

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

