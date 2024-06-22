using System.Reflection;
using UnityEngine;
using System.Linq;
using UnityEngine.Rendering;
using System.Collections;
using System;

[assembly: AssemblyVersion("1.1.1")]
namespace Deferred
{
    [KSPAddon(KSPAddon.Startup.EveryScene, false)]
    public class Deferred : MonoBehaviour
    {
        Camera firstLocalCamera, scaledCamera, editorCamera, internalCamera;
        private bool gbufferDebugModeEnabled = false;

        private static bool incompatibleShadersReplacedInExistingMaterials = false;

        private void Init()
        {
            ReplaceIncompatibleShadersInExistingMaterials();

            SetupCustomReflectionsAndAmbient();

            HandleCameras();

            HandleStockProbe();

            QualitySettings.pixelLightCount = Math.Max(GameSettings.LIGHT_QUALITY, 64);
            GameSettings.TERRAIN_SHADER_QUALITY = 3; // Only have shader replacements for the Ultra quality terrain shader
        }

        private void HandleCameras()
        {
            firstLocalCamera = RenderingUtils.FindCamera(RenderingUtils.IsUnifiedCameraMode() ? "Camera 00" : "Camera 01");
            scaledCamera = RenderingUtils.FindCamera("Camera ScaledSpace");
            editorCamera = RenderingUtils.FindCamera("Main Camera");

            EnableDeferredShadingOnCamera(firstLocalCamera);
            EnableDeferredShadingOnCamera(scaledCamera);
            EnableDeferredShadingOnCamera(editorCamera);

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
            Shader.SetGlobalMatrix(IVALightingRotation.InternalSpaceToWorld, Matrix4x4.identity);

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
            internalCamera = Camera.allCameras.FirstOrDefault(_cam => _cam.name == "InternalCamera");

            if (cameraMode == CameraManager.CameraMode.IVA)
            {
                if (internalCamera != null)
                {
                    EnableDeferredShadingOnCamera(internalCamera);
                    ToggleCameraDebugMode(internalCamera, gbufferDebugModeEnabled);

                    var dummyForwardObject = internalCamera.GetComponent<ForwardRenderingCompatibility>();

                    if (dummyForwardObject == null)
                    {
                        dummyForwardObject = internalCamera.gameObject.AddComponent<ForwardRenderingCompatibility>();
                        dummyForwardObject.Init(20);
                    }

                    var ivaLightingRotation = internalCamera.GetComponent<IVALightingRotation>();

                    if (ivaLightingRotation == null)
                    {
                        internalCamera.gameObject.AddComponent<IVALightingRotation>();
                    }
                }
            }
            else
            {
                if (internalCamera != null)
                {
                    ToggleCameraDebugMode(internalCamera, false);
                }
            }
        }


        public void ToggleDebugMode()
        {
            ToggleCameraDebugMode(firstLocalCamera, !gbufferDebugModeEnabled);
            ToggleCameraDebugMode(scaledCamera, !gbufferDebugModeEnabled);
            ToggleCameraDebugMode(internalCamera, !gbufferDebugModeEnabled);
            ToggleCameraDebugMode(editorCamera, !gbufferDebugModeEnabled);

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
            windowId = UnityEngine.Random.Range(int.MinValue, int.MaxValue);
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

            ToggleCameraDebugMode(firstLocalCamera, false);
            ToggleCameraDebugMode(scaledCamera, false);
            ToggleCameraDebugMode(internalCamera, false);
            ToggleCameraDebugMode(editorCamera, false);
        }

        bool showUI=false;
        int windowId;
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
