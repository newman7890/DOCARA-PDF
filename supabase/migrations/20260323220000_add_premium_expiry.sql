-- Add premium_expiry column to support monthly subscriptions
ALTER TABLE devices ADD COLUMN IF NOT EXISTS premium_expiry TIMESTAMPTZ;
