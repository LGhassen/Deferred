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

        private static void FixScene()
        {
            FixVABProps();
            FixSPHLights();
            FixShadowReceiver();
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
        }
    }
}
