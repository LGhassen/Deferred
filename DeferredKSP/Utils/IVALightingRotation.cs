using UnityEngine;

namespace Deferred
{ 
    public class IVALightingRotation : MonoBehaviour
    {
        public static readonly int InternalSpaceToWorld = Shader.PropertyToID("internalSpaceToWorld");

        void OnPreRender()
        {
            if (InternalSpace.Instance != null && FlightGlobals.ActiveVessel != null)
            {
                var internalToWorldMatrix = FlightGlobals.ActiveVessel.transform.localToWorldMatrix * InternalSpace.Instance.transform.localToWorldMatrix;
                Shader.SetGlobalMatrix(InternalSpaceToWorld, internalToWorldMatrix);
            }
        }

        void Update()
        {

        }

        void OnPostRender()
        {
            Shader.SetGlobalMatrix(InternalSpaceToWorld, Matrix4x4.identity);
        }
    }
}