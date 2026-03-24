-- Enable Row Level Security on the devices table to prevent unauthorized modifications
ALTER TABLE "devices" ENABLE ROW LEVEL SECURITY;

-- Block all API key access from the Supabase public anon key.
-- This ensures that hackers cannot extract the anon key from the Flutter app to manipulate their "is_premium" status.
CREATE POLICY "Block all public access"
    ON "devices"
    FOR ALL
    USING (false);

-- Why this works:
-- The Edge Functions use the SUPABASE_SERVICE_ROLE_KEY environment variable.
-- The Service Role key instantly bypasses Row Level Security (RLS) policies.
-- Because of this, only your authenticated and HMAC-signed Edge Function can interact with the table.
