-- 1. Add hardware_fingerprint column to track physical devices persistently
ALTER TABLE "devices" ADD COLUMN IF NOT EXISTS "hardware_fingerprint" TEXT;
CREATE INDEX IF NOT EXISTS idx_devices_hardware_fingerprint ON "devices"(hardware_fingerprint);

-- 2. Ensure usage columns exist with defaults
-- (In case they weren't explicitly added in a previous migration)
ALTER TABLE "devices" ADD COLUMN IF NOT EXISTS "usage_count" INTEGER DEFAULT 0;
ALTER TABLE "devices" ADD COLUMN IF NOT EXISTS "is_premium" BOOLEAN DEFAULT false;
ALTER TABLE "devices" ADD COLUMN IF NOT EXISTS "is_blocked" BOOLEAN DEFAULT false;

-- 3. Create or Update the authoritative increment function
-- This function will handle the trial logic securely on the server.
CREATE OR REPLACE FUNCTION increment_usage(d_id TEXT, h_fp TEXT = NULL)
RETURNS void AS $$
BEGIN
    -- If we have a fingerprint, we sync ALL records sharing that fingerprint
    -- This ensures that if a user uninstalls (getting a new device_id),
    -- their old usage count is instantly restored to the new ID.
    
    -- First, ensure the record exists for this device_id
    INSERT INTO "devices" (device_id, hardware_fingerprint, usage_count)
    VALUES (d_id, h_fp, 0)
    ON CONFLICT (device_id) DO UPDATE 
    SET hardware_fingerprint = EXCLUDED.hardware_fingerprint,
        last_seen = NOW();

    -- Now, increment usage for THIS device AND any others linked by fingerprint
    IF h_fp IS NOT NULL THEN
        UPDATE "devices"
        SET usage_count = usage_count + 1,
            last_seen = NOW()
        WHERE hardware_fingerprint = h_fp;
    ELSE
        UPDATE "devices"
        SET usage_count = usage_count + 1,
            last_seen = NOW()
        WHERE device_id = d_id;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
