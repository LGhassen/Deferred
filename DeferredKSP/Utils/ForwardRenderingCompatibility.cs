using System.Linq;
using UnityEngine;
using UnityEngine.Rendering;

namespace Deferred
{
    [DefaultExecutionOrder(9000)]
    public class ForwardRenderingCompatibility : MonoBehaviour
    {

        private Material material;
        private GameObject go;

        public void Init(int layer)
        {
            AddDummyForwardObject(layer);

            InitMainLightProperties();
        }

        // There are many visual mods which depend on certain commandBuffer events like AfterForwardOpaque that only
        // render if objects are being rendered in forward.
        // This dummy forward-rendered object forces these commandBuffer events to fire
        private void AddDummyForwardObject(int layer)
        {
            material = new Material(ShaderLoader.Instance.DeferredShaders["Deferred/DummyForwardShader"]);

            go = GameObject.CreatePrimitive(PrimitiveType.Quad);

            var collider = go.GetComponent<Collider>();
            if (collider != null)
            {
                Component.Destroy(collider);
            }

            var mr = go.GetComponent<MeshRenderer>();
            mr.sharedMaterial = material;
            mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            mr.receiveShadows = false;

            var mf = go.GetComponent<MeshFilter>();
            mf.mesh.bounds = new Bounds(Vector4.zero, new Vector3(1e18f, 1e18f, 1e18f));

            go.layer = layer;

            go.transform.parent = transform;
            go.transform.localPosition = Vector3.zero;
            go.SetActive(true);
        }

        private void OnDestroy()
        {
            if (go != null)
            {
                GameObject.Destroy(go);
            }
        }

        // In legacy forward rendering _LightColor0 and _WorldSpaceLightPos0 are provided as properties of the main light in all shaders
        // These aren't present in deferred for obvious reasons but get set later automatically when rendering forward opaque objects
        // We might still need them in deferred for specific usecases so set a commandBuffer to provide them
        // The DefaultExecutionOrder of the script ensures this script runs after Scatterer modifies the main light color
        private void InitMainLightProperties()
        {
            targetCamera = GetComponent<Camera>();
            commandBuffer = new CommandBuffer();

            var lights = (Light[])FindObjectsOfType(typeof(Light));
            targetLight = lights.Where(x => x.name == "SunLight").FirstOrDefault();

            // If we don't find the main light fall back to using the brightest local directional light
            if (targetLight == null)
            {
                targetLight = lights
                    .Where(light => light.type == LightType.Directional && (light.cullingMask & 1 << 15) != 0)
                    .OrderByDescending(light => light.intensity)
                    .FirstOrDefault();
            }
        }

        Camera targetCamera;
        Light targetLight;
        CommandBuffer commandBuffer;

        private static int lightColorProperty = Shader.PropertyToID("_LightColor0");
        private static int lightPosProperty = Shader.PropertyToID("_WorldSpaceLightPos0");

        private void OnPreRender()
        {
            if (targetCamera != null && targetLight != null && targetCamera.stereoActiveEye != Camera.MonoOrStereoscopicEye.Right)
            {
                commandBuffer.Clear();
                commandBuffer.SetGlobalVector(lightColorProperty, targetLight.color);
                commandBuffer.SetGlobalVector(lightPosProperty, -targetLight.transform.forward);
                targetCamera.AddCommandBuffer(CameraEvent.BeforeGBuffer, commandBuffer);
            }
        }

        private void OnPostRender()
        {
            if (targetCamera != null && commandBuffer != null && targetCamera.stereoActiveEye != Camera.MonoOrStereoscopicEye.Left)
            {
                targetCamera.RemoveCommandBuffer(CameraEvent.BeforeGBuffer, commandBuffer);
            }
        }
    }
}