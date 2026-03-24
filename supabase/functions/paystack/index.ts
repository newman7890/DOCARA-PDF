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
    const API_SECRET = Deno.env.get('API_SECRET');
    const PAYSTACK_SECRET_KEY = Deno.env.get('PAYSTACK_SECRET_KEY');

    if (!API_SECRET || !PAYSTACK_SECRET_KEY) {
      console.error("[Paystack] Missing secrets in environment!");
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

    // HMAC Verification
    const payload = timestamp + deviceId + featureName + rawBody
    const isValid = await verifySignature(API_SECRET, payload, signature)

    const requestTime = parseInt(timestamp, 10);
    const serverTime = Date.now();
    
    // Prevent Replay Attacks (5 minute window)
    if (isNaN(requestTime) || Math.abs(serverTime - requestTime) > 300000) {
      console.error(`[Paystack] Replay Attack Blocked: Timestamp too old or invalid`);
      return new Response(JSON.stringify({ error: "Request Expired" }), { 
        status: 403, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      })
    }

    const { action } = body
    console.log(`[Paystack] Action: ${action}, Device: ${deviceId}, Valid: ${isValid}`);
    
    if (!isValid) {
      console.error(`[Paystack] HMAC Mismatch!`);
      return new Response(JSON.stringify({ 
        error: "Unauthorized", 
        debug: "HMAC mismatch",
        server_payload: payload,
        secret_length: API_SECRET?.length
      }), { 
        status: 401, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      })
    }

    // --- PAYSTACK LOGIC --- //

    if (action === 'initialize') {
      const { email, amount } = body;
      const amountInSubunits = Math.round(amount * 100);
      const reference = `pdf_scanner_${globalThis.crypto.randomUUID()}`;

      const paystackRes = await fetch('https://api.paystack.co/transaction/initialize', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${PAYSTACK_SECRET_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          email: email,
          amount: amountInSubunits,
          reference: reference,
          callback_url: "https://standard.paystack.co/close",
        }),
      });

      const data = await paystackRes.json();
      if (!data.status) {
         return new Response(JSON.stringify({ success: false, error: data.message }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }

      return new Response(JSON.stringify({ 
        success: true, 
        authUrl: data.data.authorization_url,
        accessCode: data.data.access_code,
        reference: data.data.reference 
      }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'verify') {
      const { reference } = body;

      const paystackRes = await fetch(`https://api.paystack.co/transaction/verify/${reference}`, {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${PAYSTACK_SECRET_KEY}`,
          'Content-Type': 'application/json',
        },
      });

      const data = await paystackRes.json();
      if (!data.status) {
         return new Response(JSON.stringify({ success: false, error: data.message }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }

      const isSuccess = data.data.status === "success";
      return new Response(JSON.stringify({ success: isSuccess, status: data.data.status }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    return new Response(JSON.stringify({ error: "Invalid Action" }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

  } catch (err: any) {
    console.error("Function Error:", err)
    return new Response(JSON.stringify({ error: err.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
