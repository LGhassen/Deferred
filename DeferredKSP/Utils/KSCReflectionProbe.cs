using UnityEngine;

namespace Deferred
{
    [KSPAddon(KSPAddon.Startup.SpaceCentre, false)]
    public class KSCReflectionProbe : MonoBehaviour
    {
        GameObject go = null;
        ReflectionProbe probe = null;

        private void Awake()
        {
            go = new GameObject("Deferred KSC Reflection Probe");
            probe = go.AddComponent<ReflectionProbe>();

            probe.mode = UnityEngine.Rendering.ReflectionProbeMode.Realtime;
            probe.refreshMode = UnityEngine.Rendering.ReflectionProbeRefreshMode.EveryFrame;
            probe.timeSlicingMode = UnityEngine.Rendering.ReflectionProbeTimeSlicingMode.IndividualFaces;

            probe.resolution = GameSettings.REFLECTION_PROBE_TEXTURE_RESOLUTION;

            // Make the reflection probe light up objects in this range
            probe.size = new Vector3(1000000f, 1000000f, 1000000f);

            // Set only local in culling mask, scaled cannot be rendered correctly in reflectionProbe and needs separate camera, as done in scatterer
            // Here the local alone is fine as scatterer sky renders on that layer, and its only KSC anyway
            probe.cullingMask = 1 << 15;

            probe.shadowDistance = 0.0f;
            probe.hdr = false;

            probe.clearFlags = UnityEngine.Rendering.ReflectionProbeClearFlags.SolidColor;
            probe.backgroundColor = Color.black;

            probe.nearClipPlane = 0.1f;
            probe.farClipPlane = 100000f;

            probe.enabled = true;
        }

        private void OnDestroy()
        {
            go.DestroyGameObject();
        }
    }
}
