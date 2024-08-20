// DepthMask from https://web.archive.org/web/20140219002415/http://wiki.unity3d.com/index.php?title=DepthMask, modified to work in deferred
Shader "DepthMask" {
        SubShader {
        Tags { "Queue" = "Geometry-1000" "LightMode" = "Deferred"}
        
        ZWrite On
        Cull Off

        ColorMask 0
        Pass {}
    }
        SubShader {
        Tags { "Queue" = "Geometry-1000" "LightMode" = "ForwardBase"}
        
        ZWrite On
        Cull Off
        
        ColorMask 0
        Pass {}
    }
}