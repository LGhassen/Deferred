// Since we can't access the deferred reflection prbe camera directly, check if the dummy
// object is being rendered on it, if so enable deferred rendering on it

using UnityEngine;
using System.Collections.Generic;

namespace Deferred
{
	public class DeferredReflectionProbeChecker : MonoBehaviour
	{
		Dictionary<Camera,DeferredReflectionProbeFixer> camToFixer =  new Dictionary<Camera,DeferredReflectionProbeFixer>() ;

		public void OnWillRenderObject()
		{
			Camera cam = Camera.current;
			
			if (!cam)
				return;

			if (!camToFixer.ContainsKey(cam))
			{
				if (cam.name == "Reflection Probes Camera")
				{
					camToFixer[cam] = (DeferredReflectionProbeFixer) cam.gameObject.AddComponent(typeof(DeferredReflectionProbeFixer));
				}
				else
				{
					//we add it anyway to avoid doing a string compare
					camToFixer[cam] = null;
				}
			}

		}

		public void OnDestroy()
		{
			if (camToFixer.Count != 0) 
			{
				foreach (var _val in camToFixer.Values)
				{
					if (_val)
					{
						Component.DestroyImmediate (_val);
					}
				}
				camToFixer.Clear();
			}
		}
	}

    public class DeferredReflectionProbeFixer : MonoBehaviour
    {

        Camera reflectionProbeCamera;

        public void Awake()
        {
            reflectionProbeCamera = gameObject.GetComponent<Camera>();
        }

        public void OnPreCull()
        {
            reflectionProbeCamera.renderingPath = RenderingPath.DeferredShading;
        }
    }
}

