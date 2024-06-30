using System.Reflection;
using UnityEngine;
using System.Collections.Generic;
using System.IO;
using System;

namespace Deferred
{
    [KSPAddon(KSPAddon.Startup.Instantly, true)]
    public class ShaderLoader : MonoBehaviour
    {
        private static Dictionary<string, Shader> deferredShaders, replacementShaders;
        private static Dictionary<string, Texture> loadedTextures = new Dictionary<string, Texture>();

        public static Dictionary<string, Shader> ReplacementShaders { get => replacementShaders; }
        public static Dictionary<string, Shader> DeferredShaders { get => deferredShaders; }
        public static Dictionary<string, Texture> LoadedTextures { get => loadedTextures; }

        void Start()
        {
            replacementShaders = LoadAssetBundle("replacementshaders.shab");
            deferredShaders = LoadAssetBundle("deferredshaders", loadedTextures);
        }

        public Dictionary<string, Shader> LoadAssetBundle(string bundleName, Dictionary<string, Texture> texturesDictionary = null)
        {
            Dictionary<string, Shader> loadedShaders = new Dictionary<string, Shader>();

            string bundlePath = GetBundlePath(bundleName);

            using (WWW www = new WWW("file://" + bundlePath))
            {
                AssetBundle bundle = www.assetBundle;
                Shader[] shaders = bundle.LoadAllAssets<Shader>();

                foreach (Shader shader in shaders)
                {
                    loadedShaders.Add(shader.name, shader);
                }

                if (texturesDictionary != null)
                {
                    texturesDictionary.Clear();

                    Texture[] textures = bundle.LoadAllAssets<Texture>();

                    foreach (Texture texture in textures)
                    {
                        texturesDictionary.Add(texture.name, texture);
                    }
                }

                bundle.Unload(false);
                www.Dispose();
            }

            return loadedShaders;
        }

        private static string GetBundlePath(string bundleName)
        {
            string codeBase = Assembly.GetExecutingAssembly().CodeBase;
            UriBuilder uri = new UriBuilder(codeBase);

            string path = Uri.UnescapeDataString(uri.Path);
            path = Path.GetDirectoryName(path);
            path = path + "/Shaders/" + bundleName;

            return path;
        }
    }
}