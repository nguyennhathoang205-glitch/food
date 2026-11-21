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

CREATE TABLE IF NOT EXISTS public.scan_feedback (
    id BIGSERIAL PRIMARY KEY,
    user_key TEXT NOT NULL,
    predicted_class_id INTEGER,
    predicted_name TEXT,
    predicted_confidence DOUBLE PRECISION DEFAULT 0,
    corrected_class_id INTEGER,
    corrected_name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.weight_logs (
    user_key TEXT NOT NULL,
    log_date DATE NOT NULL,
    weight_kg DOUBLE PRECISION NOT NULL,
    note TEXT DEFAULT '',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_key, log_date)
);

CREATE TABLE IF NOT EXISTS public.exercise_logs (
    user_key TEXT NOT NULL,
    log_date DATE NOT NULL,
    burned_kcal INTEGER NOT NULL DEFAULT 0,
    activities JSONB NOT NULL DEFAULT '[]'::JSONB,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_key, log_date)
);

-- ============================================================================
-- Core Tables (foods, profiles, meal_logs)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.foods (
    id INTEGER PRIMARY KEY,
    name_vi TEXT NOT NULL,
    name_en TEXT DEFAULT '',
    category TEXT,
    calories_per_100g DOUBLE PRECISION NOT NULL DEFAULT 0,
    protein_g DOUBLE PRECISION NOT NULL DEFAULT 0,
    fat_g DOUBLE PRECISION NOT NULL DEFAULT 0,
    carbs_g DOUBLE PRECISION NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS public.profiles (
    user_key TEXT PRIMARY KEY,
    display_name TEXT NOT NULL DEFAULT 'Người dùng Food Scan',
    height_cm DOUBLE PRECISION,
    weight_kg DOUBLE PRECISION,
    daily_goal DOUBLE PRECISION NOT NULL DEFAULT 2000,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.meal_logs (
    id BIGSERIAL PRIMARY KEY,
    user_key TEXT NOT NULL,
    food_name TEXT NOT NULL,
    meal_type TEXT NOT NULL,
    portion_g INTEGER NOT NULL DEFAULT 150,
    calories DOUBLE PRECISION NOT NULL DEFAULT 0,
    protein_g DOUBLE PRECISION NOT NULL DEFAULT 0,
    fat_g DOUBLE PRECISION NOT NULL DEFAULT 0,
    carbs_g DOUBLE PRECISION NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_meal_logs_user_created ON public.meal_logs(user_key, created_at DESC);

-- ============================================================================
-- Community AI (CLIP + pgvector) & Community Recipes
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS public.community_foods (
    id BIGSERIAL PRIMARY KEY,
    name_vi TEXT NOT NULL,
    name_key TEXT UNIQUE NOT NULL,
    created_by TEXT NOT NULL,
    calories_per_100g DOUBLE PRECISION,
    protein_g DOUBLE PRECISION,
    fat_g DOUBLE PRECISION,
    carbs_g DOUBLE PRECISION,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.community_food_images (
    id BIGSERIAL PRIMARY KEY,
    food_id BIGINT NOT NULL REFERENCES public.community_foods(id) ON DELETE CASCADE,
    user_key TEXT NOT NULL,
    embedding vector(512) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION public.match_community_foods(
    query_embedding vector(512),
    match_count INT DEFAULT 12
)
RETURNS TABLE (
    food_id BIGINT,
    name_vi TEXT,
    similarity DOUBLE PRECISION,
    calories_per_100g DOUBLE PRECISION,
    protein_g DOUBLE PRECISION,
    fat_g DOUBLE PRECISION,
    carbs_g DOUBLE PRECISION
)
LANGUAGE sql STABLE
AS $$
    SELECT
        cf.id AS food_id,
        cf.name_vi,
        1 - (cfi.embedding <=> query_embedding) AS similarity,
        cf.calories_per_100g,
        cf.protein_g,
        cf.fat_g,
        cf.carbs_g
    FROM public.community_food_images cfi
    JOIN public.community_foods cf ON cf.id = cfi.food_id
    ORDER BY cfi.embedding <=> query_embedding
    LIMIT match_count;
$$;

CREATE TABLE IF NOT EXISTS public.recipes (
    id BIGSERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT DEFAULT '',
    servings INTEGER NOT NULL DEFAULT 1,
    ingredients JSONB NOT NULL DEFAULT '[]'::JSONB,
    steps JSONB NOT NULL DEFAULT '[]'::JSONB,
    nutrition JSONB NOT NULL DEFAULT '{}'::JSONB,
    labels JSONB NOT NULL DEFAULT '[]'::JSONB,
    thumb TEXT,
    created_by TEXT NOT NULL,
    display_name TEXT NOT NULL DEFAULT 'Người dùng FoodScan',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.recipe_likes (
    recipe_id BIGINT NOT NULL REFERENCES public.recipes(id) ON DELETE CASCADE,
    user_key TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (recipe_id, user_key)
);


