using UnityEngine;

namespace Deferred
{
    // The legacy ambient variable isn't updated for the deferred pass but gets updated when transparencies/forward objects
    // This means when scatterer overrides the ambient to disable it in scaled space, the first camera to render after
    // has this value broken for deferred objects, this force updates it faster
    public class RefreshLegacyAmbient : MonoBehaviour
    {
        public static readonly int ambientProperty = Shader.PropertyToID("legacyAmbientColor");

        void OnPreRender()
        {
            Shader.SetGlobalColor(ambientProperty, RenderSettings.ambientLight);
        }
    }
}