using UnityEngine;

namespace Deferred
{
    public class Settings
    {
        [Persistent] public float ambientBrightness = 0.9f;
        [Persistent] public float ambientTint = 0.7f;
        
        [Persistent] public bool useSmaaInEditors = true;
        [Persistent] public bool useDitheredTransparency = false;
        
        [Persistent] public KeyCode guiModifierKey;
        [Persistent] public KeyCode guiKey;

        [Persistent] public bool useScreenSpaceReflections = true;
        [Persistent] public bool useHalfResolutionScreenSpaceReflections = true;

        [Persistent] public bool capReflectionProbeRefreshRate = true;
        [Persistent] public bool capReflectionProbeResolution = true;

        public static Settings LoadSettings()
        {
            UrlDir.UrlConfig[] configs = GameDatabase.Instance.GetConfigs("Deferred");
            foreach (UrlDir.UrlConfig _url in configs)
            {
                ConfigNode[] configNodeArray = _url.config.GetNodes("Deferred_config");
                if (configNodeArray.Length > 0)
                {
                    var settings = new Settings();
                    ConfigNode.LoadObjectFromConfig(settings, configNodeArray[0]);
                    return settings;
                }
            }

            return new Settings();
        }
    }
}