import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-signature, x-timestamp, x-package-name, x-app-signature, x-integrity-token, x-risk-score, x-feature-name',
}

// Helper to verify HMAC using native Web Crypto API
async function verifySignature(secret: string, payload: string, signature: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"]
  );
  
  const sigBytes = new Uint8Array(signature.match(/.{1,2}/g)!.map(byte => parseInt(byte, 16)));
  return await crypto.subtle.verify(
    "HMAC",
    key,
    sigBytes,
    encoder.encode(payload)
  );
}

serve(async (req: any) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const API_SECRET = Deno.env.get('API_SECRET');
    if (!API_SECRET) {
      console.error("[VerifyDevice] API_SECRET not set in environment!");
      return new Response(JSON.stringify({ error: "Configuration Error" }), { status: 500, headers: corsHeaders });
    }
    
    // Extract headers
    const signature = req.headers.get('x-signature') || ''
    const timestamp = req.headers.get('x-timestamp') || ''
    const featureName = req.headers.get('x-feature-name') || ''
    
    // Read raw body as text for perfect HMAC parity
    const rawBody = await req.text()
    const body = JSON.parse(rawBody)
    const deviceId = body.device_id || 'unknown'

    // HMAC Verification (Matches ApiService.dart exactly)
    const payload = timestamp + deviceId + featureName + rawBody
    const isValid = await verifySignature(API_SECRET, payload, signature)

    const requestTime = parseInt(timestamp, 10);
    const serverTime = Date.now();
    
    // Prevent Replay Attacks (5 minute window)
    if (isNaN(requestTime) || Math.abs(serverTime - requestTime) > 300000) {
      console.error(`[VerifyDevice] Replay Attack Blocked: Timestamp too old or invalid`);
      return new Response(JSON.stringify({ error: "Request Expired" }), { 
        status: 403, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      })
    }

    const { action } = body
    console.log(`[VerifyDevice] Action: ${action}, Device: ${deviceId}, Valid: ${isValid}`);
    
    if (!isValid) {
      console.error(`[VerifyDevice] HMAC Mismatch!`);
      console.error(`  Expected Signature for payload: ${payload}`);
      console.error(`  Received Signature: ${signature}`);
      return new Response(JSON.stringify({ error: "Unauthorized", debug: "HMAC mismatch" }), { 
        status: 401, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      })
    }

    if (action === 'register') {
      const { error } = await supabaseClient.from('devices').upsert({
        device_id: body.device_id,
        hardware_fingerprint: body.hardware_fingerprint,
        install_id: body.install_id || '',
        device_model: body.device_model,
        manufacturer: body.manufacturer,
        android_version: body.android_version,
        screen_resolution: body.screen_resolution,
        cpu_architecture: body.cpu_architecture,
        last_seen: new Date().toISOString()
      }, { onConflict: 'device_id' })
      
      if (error) console.error("[VerifyDevice] Database Error (register):", error);
      return new Response(JSON.stringify({ success: !error, error }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'get_status') {
      // 1. Look up Trial usages by Device ID perfectly independently of Auth
      const { data: dData, error } = await supabaseClient
        .from('devices')
        .select('usage_count, is_blocked')
        .eq('device_id', body.device_id)
        .order('usage_count', { ascending: false })
        .limit(1)
        .maybeSingle()
      
      if (error) console.error("[VerifyDevice] Database Error (status):", error);

      // 2. Check Premium Status from Supabase Auth token
      const authHeader = req.headers.get('Authorization');
      let pData = null;

      if (authHeader) {
        const token = authHeader.replace('Bearer ', '');
        const { data: { user } } = await supabaseClient.auth.getUser(token);
        
        if (user) {
          const { data: profile } = await supabaseClient
            .from('profiles')
            .select('is_premium, premium_expiry')
            .eq('id', user.id)
            .maybeSingle();
            
          pData = profile;

          if (pData) {
            // Check if premium has expired
            const now = new Date();
            let isExpired = false;
            if (pData.premium_expiry) {
              const expiry = new Date(pData.premium_expiry);
              if (!isNaN(expiry.getTime())) {
                isExpired = now > expiry;
              } else {
                console.warn(`[VerifyDevice] Invalid premium_expiry format in DB: ${pData.premium_expiry}`);
              }
            }

            if (pData.is_premium && isExpired) {
              // Revoke premium
              await supabaseClient
                .from('profiles')
                .update({ is_premium: false })
                .eq('id', user.id);
              pData.is_premium = false;
              console.log(`[VerifyDevice] Premium expired for user ${user.id}. Revoked.`);
            }
          }
        }
      }

      return new Response(JSON.stringify({
        usage_count: dData?.usage_count || 0,
        is_premium: pData?.is_premium || false,
        is_blocked: dData?.is_blocked || false,
        premium_expiry: pData?.premium_expiry || null,
      }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'track_usage') {
      const hFp = body.hardware_fingerprint || '';
      console.log(`[VerifyDevice] Authoritative increment for ${body.device_id} (Fingerprint: ${hFp})`);
      
      // Fallback: Perform a robust increment manually against the PostgreSQL database
      const { data: currentDevice, error: readError } = await supabaseClient
        .from('devices')
        .select('usage_count')
        .eq('device_id', body.device_id)
        .single();

      if (readError) {
        console.error("[VerifyDevice] Read failed for increment:", readError);
        return new Response(JSON.stringify({ success: false, error: readError }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }

      const { error: updateError } = await supabaseClient
        .from('devices')
        .update({ usage_count: (currentDevice?.usage_count || 0) + 1 })
        .eq('device_id', body.device_id);

      if (updateError) {
        console.error("[VerifyDevice] Update failed:", updateError);
        return new Response(JSON.stringify({ success: false, error: updateError }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }
      
      return new Response(JSON.stringify({ success: true }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // HTTP Upgrade action removed entirely for security. Bypasses are now impossible.

    return new Response(JSON.stringify({ error: "Invalid Action" }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

  } catch (err: any) {
    console.error("Function Error:", err)
    return new Response(JSON.stringify({ error: err.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
