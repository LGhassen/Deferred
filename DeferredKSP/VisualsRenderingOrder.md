
## Visuals rendering order

- Opaque objects up to renderqueue 2500
- Built-in shadows
- Scatterer caustics
- EVE Cloud shadows
- TUFX SSAO (deferred)
- Deferred lighting and ambient
- Forward opaque objects
- After forward opaque camera event
	- Scatterer ocean geometry prepass
	- Scatterer/EVE ocean deferred shadows prepasses
	- EVE raymarched volumetrics cloud rendering
	- Scatterer godrays occlusion (needs ocean geometry prepass for depth)
- Before image effects opaque camera event
	- TUFX SSAO (forward)
	- Scatterer sky screencopy (needed for emulated HDR blending of both sky and clouds)
	- Sky + sky volumetrics pass
	- SSR (needs sky and sky volumetrics)
- Image effects opaque camera event
	- TUFX SSAO (forward)
- After image effects opaque camera event																
	- Scatterer ocean refractions screen copy
	- Scatterer ocean shading (needs SSR and ocean prepasses)
- Before forward alpha camera event
	- Scatterer screen copy for scattering  (needed for emulated HDR blending)
	- Local scattering (needs ocean shading and SSR)
- Volumetrics on terrain
- Transparencies
