using UnityEngine;

namespace Deferred
{
    // Only used to disable the local reflection probe being used on the scaled camera, causing weird reflections on scaled planets
    public class DisableCameraReflectionProbe : MonoBehaviour
    {
        public static readonly int UseReflectionProbeOnCurrentCameraProperty = Shader.PropertyToID("useReflectionProbeOnCurrentCamera");

        void OnPreRender()
        {
            Shader.SetGlobalInt(UseReflectionProbeOnCurrentCameraProperty, 0);
        }

        void OnPostRender()
        {
            Shader.SetGlobalInt(UseReflectionProbeOnCurrentCameraProperty, 1);
        }

        private void OnDestroy()
        {
            Shader.SetGlobalInt(UseReflectionProbeOnCurrentCameraProperty, 1);
        }
    }
}