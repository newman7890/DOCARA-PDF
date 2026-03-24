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
      // Look up by deviceID or Hardware Fingerprint to prevent resets
      const { data, error } = await supabaseClient
        .from('devices')
        .select('usage_count, is_premium, is_blocked, premium_expiry')
        .or(`device_id.eq.${body.device_id},hardware_fingerprint.eq.${body.hardware_fingerprint}`)
        .order('usage_count', { ascending: false })
        .limit(1)
        .maybeSingle()
      
      if (error) console.error("[VerifyDevice] Database Error (status):", error);

      if (data) {
        // Check if premium has expired
        const now = new Date();
        const expiry = data.premium_expiry ? new Date(data.premium_expiry) : null;
        const isExpired = expiry ? now > expiry : false;

        if (data.is_premium && isExpired) {
          // Revoke premium since subscription has lapsed
          await supabaseClient
            .from('devices')
            .update({ is_premium: false })
            .eq('device_id', body.device_id);
          data.is_premium = false;
          console.log(`[VerifyDevice] Premium expired for device ${deviceId}. Revoked.`);
        }

        return new Response(JSON.stringify({
          usage_count: data.usage_count,
          is_premium: data.is_premium,
          is_blocked: data.is_blocked,
          premium_expiry: data.premium_expiry,
        }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }

      return new Response(JSON.stringify({ usage_count: 0, is_premium: false }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
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

    if (action === 'upgrade') {
      const expiryDate = new Date();
      expiryDate.setDate(expiryDate.getDate() + 30); // 30-day subscription
      const updatePayload: any = { is_premium: true };

      // Optional: Attempt to add premium_expiry if the column exists
      // We'll try to find if the column exists by just including it and catching errors
      updatePayload.premium_expiry = expiryDate.toISOString();

      console.log(`[VerifyDevice] Attempting upgrade for Device: ${deviceId}, Fingerprint: ${body.hardware_fingerprint}`);

      // 1. Try updating by device_id OR hardware_fingerprint redundantly to ensure we hit it
      let { data, error: updateError, count } = await supabaseClient
        .from('devices')
        .update(updatePayload, { count: 'exact' })
        .or(`device_id.eq.${body.device_id},hardware_fingerprint.eq.${body.hardware_fingerprint}`);

      // 2. Fallback: If premium_expiry caused an error (column missing), retry with just is_premium
      if (updateError && updateError.message.includes('premium_expiry')) {
        console.warn("[VerifyDevice] premium_expiry column missing, falling back to is_premium only");
        delete updatePayload.premium_expiry;
        const result = await supabaseClient
          .from('devices')
          .update(updatePayload, { count: 'exact' })
          .or(`device_id.eq.${body.device_id},hardware_fingerprint.eq.${body.hardware_fingerprint}`);
        updateError = result.error;
        count = result.count;
      }

      // 3. Fallback: IF NO ROWS UPDATED, the device might not be in the table yet!
      if (!updateError && (count === 0 || count === null)) {
        console.warn("[VerifyDevice] No records found to update, performing UPSERT instead");
        const { error: upsertError } = await supabaseClient
          .from('devices')
          .upsert({
            device_id: body.device_id,
            hardware_fingerprint: body.hardware_fingerprint,
            ...updatePayload
          }, { onConflict: 'device_id' });
        updateError = upsertError;
      }

      if (updateError) {
        console.error("[VerifyDevice] Upgrade failed:", updateError);
        return new Response(JSON.stringify({ success: false, error: updateError.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      console.log(`[VerifyDevice] Premium Activation SUCCESS for ${deviceId}`);
      return new Response(JSON.stringify({ 
        success: true, 
        premium_expiry: updatePayload.premium_expiry || null 
      }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    return new Response(JSON.stringify({ error: "Invalid Action" }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

  } catch (err: any) {
    console.error("Function Error:", err)
    return new Response(JSON.stringify({ error: err.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
