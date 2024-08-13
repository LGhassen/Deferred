// Several of the KSC's ground meshes have normals that point up and don't match the geometry, including the runway
// This could be so that elements made of several sections like the runway connect seamlessly, of course this is the
// laziest way possible, in typical SQUAD fashion.
// These normals cause issues with EVE deferred puddles appearing on slopes and looking like crap, this recalculates the
// normals and tangents of the KSC ground meshes and the island runway to fix that, while keeping tarmac normals
// pointing up.
// Special logic is used for the runway because it's made of different sections and the recalculated normals where
// sections connect don't match, so they are "rounded" to the dominant normal direction to always match.
using System.Collections.Generic;
using UnityEngine;
using System.Linq;

namespace Deferred
{
    public static class KSCModelNormalsFixer
    {
        public static void FixKSCModels()
        {
            HashSet<GameObject> visitedPrefabs = new HashSet<GameObject>();

            Upgradeables.UpgradeableObject[] upgradeablefacilities;
            upgradeablefacilities = Resources.FindObjectsOfTypeAll<Upgradeables.UpgradeableObject>();

            // Fix ground normals on all the main upgradeable facilities
            foreach (var facility in upgradeablefacilities)
            {
                bool isRunway = facility.name == "Runway";
                bool isCrawlerway = facility.name == "Crawlerway";

                for (int i = 0; i < facility.UpgradeLevels.Length; i++)
                {
                    var prefab = facility.UpgradeLevels[i].facilityPrefab;

                    if (prefab != null)
                    {
                        ProcessGameObjectRecursively(prefab, visitedPrefabs, isRunway, isCrawlerway);
                    }
                }
            }

            // Fix the island airfield's ground mesh
            var islandAirfield = Resources.FindObjectsOfTypeAll<PQSCity>().FirstOrDefault(x => x.name == "IslandAirfield");
            
            if (islandAirfield != null)
            {
                ProcessGameObjectRecursively(islandAirfield.gameObject, visitedPrefabs, false, false);
            }
        }

        private static void ProcessGameObjectRecursively(GameObject obj, HashSet<GameObject> visitedPrefabs, bool isRunway, bool isCrawlerway)
        {
            if (obj == null || visitedPrefabs.Contains(obj)) return;

            var mr = obj.GetComponent<MeshRenderer>();
            var mf = obj.GetComponent<MeshFilter>();

            if (mf != null && mr != null)
            {
                // Look for the right material indicating this is a ground mesh and containing the blendmask
                var mat = mr.materials.FirstOrDefault(x => x.shader.name.Contains("Diffuse Ground KSC"));

                Texture2D blendMask = null;
                bool copiedTexture = false;

                if (mat != null)
                {
                    blendMask = mat.GetTexture("_BlendMaskTexture") as Texture2D;

                    // If the blendMask is unreadable make a temporary readable copy and release it after
                    if (blendMask != null && !blendMask.isReadable)
                    {
                        blendMask = CreateReadableTextureCopy(blendMask);
                        copiedTexture = true;
                    }
                }

                var mesh = mf.sharedMesh ?? mf.mesh;

                if (mesh != null && blendMask != null)
                {
                    mesh.RecalculateNormals();

                    // Make normals where the value read from the blendMask is 1 (for tarmac) point upwards
                    var normals = mesh.normals;
                    var uv2s = mesh.uv2;
                    var vertices = mesh.vertices;

                    if (uv2s.Length > 0 && normals.Length == vertices.Length)
                    {
                        for (int i = 0; i < vertices.Length; i++)
                        {
                            // Sample the blend mask at the UV2 coordinate
                            Vector2 uv2 = uv2s[i];
                            Color blendColor = blendMask.GetPixelBilinear(uv2.x, uv2.y);

                            if (!isCrawlerway)
                            { 
                                // Make all tarmac/asphalt normals point up
                                normals[i] = Vector3.Lerp(normals[i], Vector3.up, blendColor.r);
                            }

                            // Fix the different chunks of runway not connecting because of mismatching edges
                            if (isRunway)
                            {
                                if (Mathf.Abs(normals[i].x) > 0.2f * Mathf.Abs(normals[i].z))
                                {
                                    normals[i].z = 0.0f;
                                }
                                else //if (Mathf.Abs(normals[i].z) > Mathf.Abs(normals[i].x))
                                {
                                    normals[i].x = 0.0f;
                                }

                                normals[i].Normalize();
                            }
                        }

                        if (copiedTexture)
                        {
                            GameObject.Destroy(blendMask);
                        }

                        mesh.normals = normals;
                        mesh.RecalculateTangents();
                    }
                }
            }

            visitedPrefabs.Add(obj);

            foreach (Transform child in obj.transform)
            {
                ProcessGameObjectRecursively(child.gameObject, visitedPrefabs, isRunway, isCrawlerway);
            }
        }

        private static Texture2D CreateReadableTextureCopy(Texture2D sourceTexture)
        {
            Texture2D readableTexture = new Texture2D(sourceTexture.width, sourceTexture.height, TextureFormat.R8, false);

            RenderTexture renderTexture = RenderTexture.GetTemporary(
                sourceTexture.width,
                sourceTexture.height,
                0,
                RenderTextureFormat.R8
            );

            Graphics.Blit(sourceTexture, renderTexture);

            // Copy the RenderTexture to the new readable Texture2D
            RenderTexture previous = RenderTexture.active;
            RenderTexture.active = renderTexture;

            readableTexture.ReadPixels(new Rect(0, 0, renderTexture.width, renderTexture.height), 0, 0);
            readableTexture.Apply();

            RenderTexture.active = previous;

            RenderTexture.ReleaseTemporary(renderTexture);

            return readableTexture;
        }
    }
}