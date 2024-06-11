using System.Reflection;
using UnityEngine;
using System.Linq;
using UnityEngine.Rendering;
using System.Collections.Generic;
using System.Collections;
using System;

[assembly: AssemblyVersion("1.0")]
namespace Deferred
{
    [KSPAddon(KSPAddon.Startup.EveryScene, false)]
    public class Deferred : MonoBehaviour
    {
        private List<Camera> targetCameras = new List<Camera>();
        private bool gbufferDebugModeEnabled = false;

        private static bool incompatibleShadersReplacedInExistingMaterials = false;

        private void Init()
        {
            ReplaceIncompatibleShadersInExistingMaterials();

            SetupCustomReflectionsAndAmbient();

            HandleCameras();

            HandleStockProbe();
        }

        private void HandleCameras()
        {
            // "Main Camera" is the editor parts camera
            List<string> targetCameraNames = new List<string>() { "Camera ScaledSpace", "Camera 00", "Camera 01", "Main Camera" };

            targetCameras = Camera.allCameras.Where(x => targetCameraNames.Contains(x.name)).
                OrderBy(camera => targetCameraNames.IndexOf(camera.name)).ToList();

            foreach (var camera in targetCameras)
            {
                EnableDeferredShadingOnCamera(camera);
            }

            var firstLocalCamera = RenderingUtils.IsUnifiedCameraMode() ? targetCameras.ElementAt(1) : targetCameras.ElementAt(2);

            if (firstLocalCamera != null)
            {
                var pqsFadeScript = firstLocalCamera.GetComponent<DeferredPQSFade>();

                if (pqsFadeScript == null)
                {
                    firstLocalCamera.gameObject.AddComponent<DeferredPQSFade>();
                }

                var forwardRenderingCompatibility = firstLocalCamera.GetComponent<ForwardRenderingCompatibility>();

                if (forwardRenderingCompatibility == null)
                {
                    forwardRenderingCompatibility = firstLocalCamera.gameObject.AddComponent<ForwardRenderingCompatibility>();
                    forwardRenderingCompatibility.Init(15);
                }

                var refreshLegacyAmbient = firstLocalCamera.GetComponent<RefreshLegacyAmbient>();

                if (refreshLegacyAmbient == null)
                {
                    firstLocalCamera.gameObject.AddComponent<RefreshLegacyAmbient>();
                }
            }

            var scaledCamera = targetCameras.ElementAt(0);

            if (scaledCamera != null)
            {
                var disableProbeScript = scaledCamera.GetComponent<DisableCameraReflectionProbe>();

                if (disableProbeScript == null)
                {
                    scaledCamera.gameObject.AddComponent<DisableCameraReflectionProbe>();
                }

                var forwardRenderingCompatibility = scaledCamera.GetComponent<ForwardRenderingCompatibility>();

                if (forwardRenderingCompatibility == null)
                {
                    forwardRenderingCompatibility = scaledCamera.gameObject.AddComponent<ForwardRenderingCompatibility>();
                    forwardRenderingCompatibility.Init(10);
                }

                var refreshLegacyAmbient = scaledCamera.GetComponent<RefreshLegacyAmbient>();

                if (refreshLegacyAmbient == null)
                {
                    scaledCamera.gameObject.AddComponent<RefreshLegacyAmbient>();
                }
            }

            Shader.SetGlobalInt(DisableCameraReflectionProbe.UseReflectionProbeOnCurrentCameraProperty, 1);

            GameEvents.OnCameraChange.Add(OnCameraChange);
        }

        private void HandleStockProbe()
        {
            var flightCamera = FlightCamera.fetch;
            if (flightCamera != null)
            {
                var reflectionProbe = flightCamera.reflectionProbe;
                if (reflectionProbe != null)
                {
                    var probeComponent = reflectionProbe.probeComponent;
                    if  (probeComponent != null)
                    {
                        float size = Mathf.Max(1000000f, probeComponent.size.x);
                        probeComponent.size = new Vector3(size, size, size);
                    }
                }
            }
        }

        private void EnableDeferredShadingOnCamera(Camera camera)
        {
            if (camera != null)
            {
                camera.renderingPath = RenderingPath.DeferredShading;
            }
        }

        private static void SetupCustomReflectionsAndAmbient()
        {
            GraphicsSettings.SetShaderMode(BuiltinShaderType.DeferredReflections, BuiltinShaderMode.UseCustom);
            GraphicsSettings.SetCustomShader(BuiltinShaderType.DeferredReflections,
                ShaderLoader.Instance.DeferredShaders["Deferred/Internal-DeferredReflections"]);

            var settings = Settings.LoadSettings();
            Shader.SetGlobalFloat("deferredAmbientBrightness", settings.ambientBrightness);
            Shader.SetGlobalFloat("deferredAmbientTint", settings.ambientTint);
            Shader.SetGlobalInt("editorLightingMode", HighLogic.LoadedSceneIsEditor ? 1 : 0);
        }

        // Replaces stock shaders which don't have deferred passes with replacements that do
        // Only done once at the main menu for already existing materials
        // Newer materials get the replaced shaders from shabby which replaces Shader.Find
        private void ReplaceIncompatibleShadersInExistingMaterials()
        {
            if (!incompatibleShadersReplacedInExistingMaterials && HighLogic.LoadedScene == GameScenes.MAINMENU)
            { 
                Debug.Log("[Deferred] Replacing shaders for deferred rendering");

                foreach (Material mat in Resources.FindObjectsOfTypeAll<Material>())
                {
                    string name = mat.shader.name;

                    // Some materials have overridden renderqueues not matching the shader ones
                    // These get overridden by replacing the shader
                    // Keep the original ones because they are important for parts with depthMasks
                    int originalRenderqueue = mat.renderQueue;

                    if (ShaderLoader.Instance.ReplacementShaders.TryGetValue(name, out Shader replacementShader))
                    {
                        mat.shader = replacementShader;
                    }

                    mat.renderQueue = originalRenderqueue;
                }

                incompatibleShadersReplacedInExistingMaterials = true;
            }
        }

        public void OnCameraChange(CameraManager.CameraMode cameraMode)
        {
            Camera internalCamera = Camera.allCameras.FirstOrDefault(_cam => _cam.name == "InternalCamera");

            if (cameraMode == CameraManager.CameraMode.IVA)
            {
                if (internalCamera != null)
                {
                    targetCameras.Add(internalCamera);
                    EnableDeferredShadingOnCamera(internalCamera);
                    ToggleCameraDebugMode(internalCamera, gbufferDebugModeEnabled);

                    var dummyForwardObject = internalCamera.GetComponent<ForwardRenderingCompatibility>();

                    if (dummyForwardObject == null)
                    {
                        dummyForwardObject = internalCamera.gameObject.AddComponent<ForwardRenderingCompatibility>();
                        dummyForwardObject.Init(20);
                    }
                }
            }
            else
            {
                if (internalCamera != null)
                {
                    targetCameras.Remove(internalCamera);
                    ToggleCameraDebugMode(internalCamera, false);
                }

                targetCameras.RemoveAll(x => x == null);
            }
        }


        public void ToggleDebugMode()
        {
            foreach (var camera in targetCameras)
            {
                ToggleCameraDebugMode(camera, !gbufferDebugModeEnabled);
            }

            gbufferDebugModeEnabled = !gbufferDebugModeEnabled;
        }

        private void ToggleCameraDebugMode(Camera camera, bool enable)
        {
            if (camera != null)
            {
                var debugScript = camera.GetComponent<GBufferDebug>();

                if (enable && debugScript == null)
                {
                    camera.gameObject.AddComponent<GBufferDebug>();
                }
                else if (!enable && debugScript != null)
                {
                    Component.Destroy(debugScript);
                }
            }
        }

        private void Start()
        {
            StartCoroutine(DelayedInit());
        }

        IEnumerator DelayedInit()
        {
            // Wait a few frames for the game to finish setting up
            for (int i = 0; i < 6; i++)
            {
                yield return new WaitForFixedUpdate();
            }

            Init();
        }

        public void OnDestroy()
        {
            try { StopAllCoroutines(); }
            catch (Exception) { }

            GameEvents.OnCameraChange.Remove(OnCameraChange);

            foreach(var camera in targetCameras)
            {
                ToggleCameraDebugMode(camera, false);
            }
        }

        bool showUI=false;
        int windowId = UnityEngine.Random.Range(int.MinValue, int.MaxValue);
        Rect windowRect = new Rect(20, 50, 200, 150);

        void OnGUI()
        {
            if (GameSettings.MODIFIER_KEY.GetKey() && Input.GetKeyDown(KeyCode.D))
            {
                showUI = true;
            }

            if (showUI)
            {

                windowRect = GUILayout.Window(windowId, windowRect, DrawWindow,
                    $"Deferred {Assembly.GetExecutingAssembly().GetName().Version}");
            }
        }

        void DrawWindow(int windowID)
        {
            GUILayout.Label("Debug Mode:");

            if (GUILayout.Button(gbufferDebugModeEnabled ? "Disable" : "Enable"))
            {
                ToggleDebugMode();
            }

            if (gbufferDebugModeEnabled)
            {
                GUILayout.Label("GBuffer Debug Mode:");

                if (GUILayout.Button(GBufferDebug.debugMode.ToString()))
                {
                    int enumCount = System.Enum.GetValues(typeof(GBufferDebug.DebugMode)).Length;
                    GBufferDebug.debugMode = (GBufferDebug.DebugMode)(((int)(GBufferDebug.debugMode) + 1) % enumCount);
                }
            }


            GUILayout.BeginHorizontal();
            GUILayout.Label("Blinn-Phong Shininess conversion power");
            blinnPhongShininessPower = (float)(float.Parse(GUILayout.TextField(blinnPhongShininessPower.ToString("0.000"))));
            GUILayout.EndHorizontal();

            if (GUILayout.Button("Close"))
            {
                showUI = false;
            }

            GUI.DragWindow();
        }

        // TODO: remove this debug setting
        static float blinnPhongShininessPower = 0.215f;

        void Update()
        {
            Shader.SetGlobalFloat("blinnPhongShininessPower", blinnPhongShininessPower);
        }
    }
}
