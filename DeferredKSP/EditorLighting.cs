using UnityEngine;
using System.Linq;
using UnityEngine.SceneManagement;

namespace Deferred
{
    [KSPAddon(KSPAddon.Startup.EditorAny, false)]
    public class EditorLighting : MonoBehaviour
    {
        SubpixelMorphologicalAntialiasing smaaScript = null;
        Settings setttings;

        private void Start()
        {
            // Detect soft scene changes between editors
            SceneManager.sceneLoaded += OnSceneLoaded;

            Apply();
        }

        private void OnSceneLoaded(Scene scene, LoadSceneMode mode)
        {
            Apply();
        }

        private void Apply()
        {
            HandleSMAA();
            FixScene();
        }

        private void FixScene()
        {
            FixVABProps();
            FixSPHLights();
            FixShadowReceiver();
            FixReflections();
        }

        private static void FixSPHLights()
        {
            GameObject sphSpotLight = GameObject.Find("Realtime_SpotlightCraft");

            if (sphSpotLight != null)
            {
                var light = sphSpotLight.GetComponent<Light>();

                if (light != null)
                {
                    light.range = 500f;
                    light.spotAngle = 130f;
                    light.innerSpotAngle = 100f;
                    light.intensity = 0.7f;
                }
            }

            GameObject sphWindowLight = GameObject.Find("Realtime_SpotlightWindow");

            if (sphWindowLight != null)
            {
                var light = sphWindowLight.GetComponent<Light>();

                if (light != null)
                {
                    light.range = 500f;
                    light.spotAngle = 130f;
                    light.innerSpotAngle = 100f;
                    light.intensity = 0.3f;
                }
            }
        }

        private static void FixShadowReceiver()
        {
            GameObject shadowPlane = GameObject.Find("ShadowPlane");

            if (shadowPlane != null)
            {
                var mr = shadowPlane.GetComponent<MeshRenderer>();

                if (mr != null && mr.material != null)
                {
                    int originalRenderqueue = mr.material.renderQueue;
                    mr.material.shader = ShaderLoader.Instance.ReplacementShaders["KSP/Scenery/Invisible Shadow Receiver"];
                    mr.material.renderQueue = originalRenderqueue;
                }
            }
        }

        private static void FixVABProps()
        {
            // Bring the VAB props to the layer that gets lit by the main light, otherwise they look too dark
            GameObject vabProps = GameObject.Find("model_vab_interior_props_v16");

            if (vabProps != null)
            {
                vabProps.layer = 0;
            }
        }

        GameObject probeGo;

        private void FixReflections()
        {
            // Disable the default KSP VAB/SPH cuebmaps which don't have the same convolution as reflectionprobes causing materials to appear way glossier
            RenderSettings.customReflection = null;
            RenderSettings.defaultReflectionMode = UnityEngine.Rendering.DefaultReflectionMode.Custom;

            // Spawn an accurate probe, but only render reflections on startup
            if (probeGo != null)
            {
                probeGo.DestroyGameObject();
            }

            probeGo = new GameObject("Deferred VAB/SPH Reflection Probe");
            probeGo.transform.position = new Vector3(0f, 10f, 0f);

            var probe = probeGo.AddComponent<ReflectionProbe>();

            probe.resolution = Mathf.Max(1024, GameSettings.REFLECTION_PROBE_TEXTURE_RESOLUTION);
            probe.size = new Vector3(1000000f, 1000000f, 1000000f);
            probe.cullingMask = 1 << 15;
            probe.shadowDistance = 0.0f;
            probe.clearFlags = UnityEngine.Rendering.ReflectionProbeClearFlags.Skybox;
            probe.nearClipPlane = 0.1f;
            probe.farClipPlane = 100000f;

            probe.mode = UnityEngine.Rendering.ReflectionProbeMode.Realtime;
            probe.timeSlicingMode = UnityEngine.Rendering.ReflectionProbeTimeSlicingMode.NoTimeSlicing;
            probe.refreshMode = UnityEngine.Rendering.ReflectionProbeRefreshMode.ViaScripting;

            probe.hdr = true;
            probe.intensity = 1.25f; // Make reflections brighter for punchier ambient and reflections

            probe.enabled = true;
            probe.RenderProbe();
        }

        private void HandleSMAA()
        {
            var settings = Settings.LoadSettings();
            var editorCamera = Camera.allCameras.FirstOrDefault(_cam => _cam.name == "Main Camera");

            if (editorCamera != null)
            {
                var smaa = editorCamera.gameObject.GetComponent<SubpixelMorphologicalAntialiasing>();
                if (smaa != null)
                {
                    Destroy(smaa);
                }

                if (settings.useSmaaInEditors)
                {
                    smaaScript = editorCamera.gameObject.AddComponent<SubpixelMorphologicalAntialiasing>();
                }
            }
        }

        private void OnDestroy()
        {
            SceneManager.sceneLoaded -= OnSceneLoaded;

            if (smaaScript != null)
            {
                Destroy(smaaScript);
            }

            if (probeGo != null)
            {
                probeGo.DestroyGameObject();
            }
        }
    }
}
