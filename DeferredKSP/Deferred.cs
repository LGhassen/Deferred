using System.Reflection;
using UnityEngine;
using System.Linq;
using UnityEngine.Rendering;
using System.Collections;
using System;
using UnityEngine.SceneManagement;

[assembly: AssemblyVersion("1.1.11")]
[assembly: KSPAssemblyDependency("0Harmony", 0, 0)]
[assembly: KSPAssemblyDependency("Shabby", 0, 0)]
namespace Deferred
{
    [KSPAddon(KSPAddon.Startup.MainMenu, true)]
    public class Deferred : MonoBehaviour
    {
        Camera nearCamera, firstLocalCamera, scaledCamera, editorCamera, internalCamera;
        private bool gbufferDebugModeEnabled = false;
        private Settings settings;

        void OnSceneLoaded(Scene scene, LoadSceneMode mode)
        {
            SetupCustomReflectionsAndAmbient(settings);

            HandleCameras();

            HandleStockProbe();

            QualitySettings.pixelLightCount = Math.Max(GameSettings.LIGHT_QUALITY, 64);
            GameSettings.TERRAIN_SHADER_QUALITY = 3; // I only have shader replacements for the Ultra quality terrain shaders

            GameSettings.REFLECTION_PROBE_REFRESH_MODE = Math.Max(GameSettings.REFLECTION_PROBE_REFRESH_MODE, 1);
            GameSettings.REFLECTION_PROBE_TEXTURE_RESOLUTION = Math.Max(GameSettings.REFLECTION_PROBE_TEXTURE_RESOLUTION, 0);
            GameSettings.REFLECTION_PROBE_TEXTURE_RESOLUTION = Math.Min(GameSettings.REFLECTION_PROBE_TEXTURE_RESOLUTION, 4);

            if (settings.useDitheredTransparency)
            { 
                Shader.SetGlobalTexture("_DeferredDitherBlueNoise", ShaderLoader.LoadedTextures["DeferredDitherBlueNoise"]);
                Shader.SetGlobalInt("_DeferredUseDitheredTransparency", 1);
            }
            else
            {
                Shader.SetGlobalTexture("_DeferredDitherBlueNoise", Texture2D.whiteTexture);
                Shader.SetGlobalInt("_DeferredUseDitheredTransparency", 0);
            }
        }

        private void HandleCameras()
        {
            firstLocalCamera = RenderingUtils.FindCamera(RenderingUtils.IsUnifiedCameraMode() ? "Camera 00" : "Camera 01");
            nearCamera = RenderingUtils.FindCamera("Camera 00");
            scaledCamera = RenderingUtils.FindCamera("Camera ScaledSpace");
            editorCamera = RenderingUtils.FindCamera("Main Camera");

            EnableDeferredShadingOnCamera(firstLocalCamera);

            if (!RenderingUtils.IsUnifiedCameraMode() && nearCamera != null)
            {
                EnableDeferredShadingOnCamera(nearCamera);
            }

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

        private static void SetupCustomReflectionsAndAmbient(Settings settings)
        {
            GraphicsSettings.SetShaderMode(BuiltinShaderType.DeferredReflections, BuiltinShaderMode.UseCustom);
            GraphicsSettings.SetCustomShader(BuiltinShaderType.DeferredReflections,
                ShaderLoader.DeferredShaders["Deferred/Internal-DeferredReflections"]);

            Shader.SetGlobalFloat("deferredAmbientBrightness", settings.ambientBrightness);
            Shader.SetGlobalFloat("deferredAmbientTint", settings.ambientTint);
        }

        // Replaces stock shaders which don't have deferred passes with replacements that do
        // Only done once at the main menu for already existing materials
        // Newer materials get the replaced shaders from shabby which replaces Shader.Find
        private void ReplaceIncompatibleShadersInExistingMaterials()
        {
            Debug.Log("[Deferred] Replacing shaders for deferred rendering");

            foreach (Material mat in Resources.FindObjectsOfTypeAll<Material>())
            {
                string name = mat.shader.name;

                // Some materials have overridden renderqueues not matching the shader ones
                // These get overridden by replacing the shader
                // Keep the original ones because they are important for parts with depthMasks
                int originalRenderqueue = mat.renderQueue;

                if (ShaderLoader.ReplacementShaders.TryGetValue(name, out Shader replacementShader))
                {
                    mat.shader = replacementShader;
                }

                mat.renderQueue = originalRenderqueue;
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
            if (!RenderingUtils.IsUnifiedCameraMode() && nearCamera != null)
            {
                ToggleCameraDebugMode(nearCamera, !gbufferDebugModeEnabled);
            }

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
            DontDestroyOnLoad(this);

            windowId = UnityEngine.Random.Range(int.MinValue, int.MaxValue);

            settings = Settings.LoadSettings();

            ReplaceIncompatibleShadersInExistingMaterials();

            SceneManager.sceneLoaded += OnSceneLoaded;

            OnSceneLoaded(new Scene(), LoadSceneMode.Single);
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

            SceneManager.sceneLoaded -= OnSceneLoaded;
        }

        bool showUI = false;
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

            if (GUILayout.Button("Close"))
            {
                showUI = false;
            }

            GUI.DragWindow();
        }
    }
}
