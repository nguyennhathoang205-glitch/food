-- ============================================================================
-- FoodScan AI — Stage 3 Supabase Cloud Persistence Migration
-- Chay script nay trong Supabase SQL Editor de dong bo toan bo du lieu
-- Auth, Ho so Y te (Di ung / Benh ly / Thuoc) va Nhat ky Nuoc uong len Cloud.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.app_users (
    id TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    salt TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::BIGINT
);

CREATE INDEX IF NOT EXISTS idx_app_users_email ON public.app_users(email);

CREATE TABLE IF NOT EXISTS public.health_profiles (
    user_key TEXT PRIMARY KEY,
    allergies JSONB NOT NULL DEFAULT '[]'::JSONB,
    conditions JSONB NOT NULL DEFAULT '[]'::JSONB,
    medications JSONB NOT NULL DEFAULT '[]'::JSONB,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.water_logs (
    user_key TEXT NOT NULL,
    log_date DATE NOT NULL,
    ml INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_key, log_date)
);

CREATE INDEX IF NOT EXISTS idx_water_logs_user_date ON public.water_logs(user_key, log_date);

CREATE TABLE IF NOT EXISTS public.feedback_logs (
    id BIGSERIAL PRIMARY KEY,
    user_key TEXT NOT NULL,
    predicted_name TEXT,
    predicted_class_id INTEGER,
    actual_name TEXT NOT NULL,
    actual_class_id INTEGER,
    confidence DOUBLE PRECISION,
    notes TEXT,
    bounding_box JSONB,
    image_filename TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

