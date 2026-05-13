

CREATE TABLE IF NOT EXISTS routes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    route_number TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    type TEXT DEFAULT 'bus',
    color_hex TEXT DEFAULT '#2563EB',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS route_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    route_id UUID REFERENCES routes(id) ON DELETE CASCADE,
    direction TEXT NOT NULL CHECK (direction IN ('outbound', 'inbound')),
    origin_name TEXT NOT NULL,
    destination_name TEXT NOT NULL,
    base_duration_minutes INTEGER DEFAULT 60,
    distance_km NUMERIC DEFAULT 0,
    polyline_coords JSONB DEFAULT '[]',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS stops (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    address TEXT,
    lat NUMERIC NOT NULL,
    lng NUMERIC NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(name, lat, lng)
);

CREATE TABLE IF NOT EXISTS route_stop_sequences (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    route_variant_id UUID REFERENCES route_variants(id) ON DELETE CASCADE,
    stop_id UUID REFERENCES stops(id) ON DELETE CASCADE,
    sequence_order INTEGER NOT NULL,
    walking_meters INTEGER DEFAULT 0,
    UNIQUE(route_variant_id, stop_id),
    UNIQUE(route_variant_id, sequence_order)
);

CREATE TABLE IF NOT EXISTS service_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    route_id UUID REFERENCES routes(id) ON DELETE CASCADE,
    profile_name TEXT NOT NULL DEFAULT 'Default',
    service_type TEXT NOT NULL DEFAULT 'interval',
    day_type TEXT NOT NULL CHECK (day_type IN ('weekday', 'weekend', 'holiday', 'all')),
    window_start TIME NOT NULL DEFAULT '00:00',
    window_end TIME NOT NULL DEFAULT '23:59',
    interval_minutes INTEGER NOT NULL DEFAULT 20,
    delay_factor_minutes INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='service_profiles' AND column_name='profile_name') THEN
        ALTER TABLE service_profiles ADD COLUMN profile_name TEXT NOT NULL DEFAULT 'Default';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='service_profiles' AND column_name='service_type') THEN
        ALTER TABLE service_profiles ADD COLUMN service_type TEXT NOT NULL DEFAULT 'interval';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='service_profiles' AND column_name='start_time')
       AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='service_profiles' AND column_name='window_start') THEN
        ALTER TABLE service_profiles RENAME COLUMN start_time TO window_start;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='service_profiles' AND column_name='end_time')
       AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='service_profiles' AND column_name='window_end') THEN
        ALTER TABLE service_profiles RENAME COLUMN end_time TO window_end;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='service_profiles' AND column_name='headway_minutes')
       AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='service_profiles' AND column_name='interval_minutes') THEN
        ALTER TABLE service_profiles RENAME COLUMN headway_minutes TO interval_minutes;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='service_profiles' AND column_name='delay_factor_minutes') THEN
        ALTER TABLE service_profiles ADD COLUMN delay_factor_minutes INTEGER DEFAULT 0;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS fixed_departures (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    route_variant_id UUID REFERENCES route_variants(id) ON DELETE CASCADE,
    day_type TEXT NOT NULL CHECK (day_type IN ('weekday', 'weekend', 'holiday', 'all')),
    departure_time TIME NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS live_bus_positions (
    bus_number       TEXT PRIMARY KEY,
    route_number     TEXT NOT NULL,
    route_name       TEXT,
    latitude         NUMERIC NOT NULL,
    longitude        NUMERIC NOT NULL,
    speed            NUMERIC DEFAULT 0,
    heading          NUMERIC DEFAULT 0,
    status           TEXT DEFAULT 'on_time',
    headway_minutes  INTEGER DEFAULT 20,
    next_bus_due_at  TIMESTAMP WITH TIME ZONE,
    last_updated_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    driver_id        UUID REFERENCES auth.users(id)
);

DO $$
BEGIN

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='live_bus_positions' AND column_name='driver_id') THEN
        ALTER TABLE live_bus_positions ADD COLUMN driver_id UUID REFERENCES auth.users(id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='live_bus_positions' AND column_name='next_bus_due_at') THEN
        ALTER TABLE live_bus_positions ADD COLUMN next_bus_due_at TIMESTAMP WITH TIME ZONE;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS driver_profiles (
    bus_number TEXT PRIMARY KEY,
    route_number TEXT NOT NULL,
    route_name TEXT,
    headway_minutes INTEGER DEFAULT 20,
    last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE route_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE stops ENABLE ROW LEVEL SECURITY;
ALTER TABLE route_stop_sequences ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE fixed_departures ENABLE ROW LEVEL SECURITY;
ALTER TABLE live_bus_positions ENABLE ROW LEVEL SECURITY;
ALTER TABLE driver_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read routes"           ON routes;
CREATE POLICY "Public read routes"          ON routes           FOR SELECT USING (true);
DROP POLICY IF EXISTS "Public read variants"          ON route_variants;
CREATE POLICY "Public read variants"         ON route_variants   FOR SELECT USING (true);
DROP POLICY IF EXISTS "Public read stops"             ON stops;
CREATE POLICY "Public read stops"            ON stops            FOR SELECT USING (true);
DROP POLICY IF EXISTS "Public read sequences"         ON route_stop_sequences;
CREATE POLICY "Public read sequences"        ON route_stop_sequences FOR SELECT USING (true);
DROP POLICY IF EXISTS "Public read svc profiles"      ON service_profiles;
CREATE POLICY "Public read svc profiles"     ON service_profiles FOR SELECT USING (true);
DROP POLICY IF EXISTS "Public read fixed deps"        ON fixed_departures;
CREATE POLICY "Public read fixed deps"       ON fixed_departures FOR SELECT USING (true);
DROP POLICY IF EXISTS "Public read live buses"        ON live_bus_positions;
CREATE POLICY "Public read live buses"       ON live_bus_positions FOR SELECT USING (true);
DROP POLICY IF EXISTS "Public read driver profiles"   ON driver_profiles;
CREATE POLICY "Public read driver profiles"  ON driver_profiles  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Drivers insert live"  ON live_bus_positions;
CREATE POLICY "Drivers insert live"  ON live_bus_positions
    FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Drivers update live"  ON live_bus_positions;
CREATE POLICY "Drivers update live"  ON live_bus_positions
    FOR UPDATE USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Drivers delete live"  ON live_bus_positions;
CREATE POLICY "Drivers delete live"  ON live_bus_positions
    FOR DELETE USING (true);

DROP POLICY IF EXISTS "Drivers insert profile" ON driver_profiles;
CREATE POLICY "Drivers insert profile" ON driver_profiles FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "Drivers update profile" ON driver_profiles;
CREATE POLICY "Drivers update profile" ON driver_profiles FOR UPDATE USING (true);
DROP POLICY IF EXISTS "Drivers delete profile" ON driver_profiles;
CREATE POLICY "Drivers delete profile" ON driver_profiles FOR DELETE USING (true);

DELETE FROM routes
WHERE id NOT IN (
    SELECT DISTINCT ON (route_number) id
    FROM routes
    ORDER BY route_number, id DESC
);

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'routes'::regclass AND conname = 'routes_route_number_key'
    ) THEN
        ALTER TABLE routes ADD CONSTRAINT routes_route_number_key UNIQUE (route_number);
    END IF;
END $$;

INSERT INTO routes (route_number, name) VALUES
    ('128', 'Kottawa - Thalagala via Homagama'),
    ('129', 'Kottawa - Moragahahena via Homagama'),
    ('280', 'Maharagama - Horana'),
    ('138', 'Maharagama - Colombo Fort'),
    ('120', 'Kesbewa - Pettah'),
    ('154', 'Angulana - Kiribathgoda'),
    ('100', 'Colombo - Kandy'),
    ('101', 'Colombo - Negombo'),
    ('122', 'Awissawella - Colombo'),
    ('124', 'Colombo - Kaduwela'),
    ('125', 'Colombo - Kadawatha'),
    ('131', 'Colombo - Ratmalana')
ON CONFLICT DO NOTHING;

INSERT INTO stops (name, lat, lng) VALUES
    ('Pettah Main Bus Stand',    6.9369, 79.8503),
    ('Fort Railway Station',     6.9330, 79.8510),
    ('Maharagama Bus Stand',     6.8469, 79.9282),
    ('Kottawa Bus Stand',        6.8453, 80.0027),
    ('Homagama Bus Stand',       6.8401, 80.0044),
    ('Thalagala',                6.7820, 80.0550),
    ('Moragahahena',             6.7720, 80.0400),
    ('Horana Bus Stand',         6.7150, 80.0600),
    ('Maharagama Junction',      6.8480, 79.9265),
    ('Panadura Bus Stand',       6.7132, 79.9023),
    ('Ratmalana Bus Stand',      6.8218, 79.8832)
ON CONFLICT DO NOTHING;

INSERT INTO route_variants (route_id, direction, origin_name, destination_name, base_duration_minutes, polyline_coords)
SELECT id, 'outbound', 'Kottawa', 'Thalagala', 45,
    '[[80.0027,6.8453],[80.0044,6.8401],[80.0200,6.8200],[80.0380,6.8100],[80.0550,6.7820]]'::jsonb
FROM routes WHERE route_number = '128'
AND NOT EXISTS (SELECT 1 FROM route_variants rv JOIN routes r ON rv.route_id=r.id WHERE r.route_number='128' AND rv.direction='outbound');

INSERT INTO route_variants (route_id, direction, origin_name, destination_name, base_duration_minutes, polyline_coords)
SELECT id, 'inbound', 'Thalagala', 'Kottawa', 45,
    '[[80.0550,6.7820],[80.0380,6.8100],[80.0200,6.8200],[80.0044,6.8401],[80.0027,6.8453]]'::jsonb
FROM routes WHERE route_number = '128'
AND NOT EXISTS (SELECT 1 FROM route_variants rv JOIN routes r ON rv.route_id=r.id WHERE r.route_number='128' AND rv.direction='inbound');

INSERT INTO route_variants (route_id, direction, origin_name, destination_name, base_duration_minutes, polyline_coords)
SELECT id, 'outbound', 'Maharagama', 'Horana', 60,
    '[[79.9282,6.8469],[79.9450,6.8300],[79.9700,6.8100],[80.0100,6.7800],[80.0600,6.7150]]'::jsonb
FROM routes WHERE route_number = '280'
AND NOT EXISTS (SELECT 1 FROM route_variants rv JOIN routes r ON rv.route_id=r.id WHERE r.route_number='280' AND rv.direction='outbound');

INSERT INTO route_variants (route_id, direction, origin_name, destination_name, base_duration_minutes, polyline_coords)
SELECT id, 'inbound', 'Horana', 'Maharagama', 60,
    '[[80.0600,6.7150],[80.0100,6.7800],[79.9700,6.8100],[79.9450,6.8300],[79.9282,6.8469]]'::jsonb
FROM routes WHERE route_number = '280'
AND NOT EXISTS (SELECT 1 FROM route_variants rv JOIN routes r ON rv.route_id=r.id WHERE r.route_number='280' AND rv.direction='inbound');

INSERT INTO route_variants (route_id, direction, origin_name, destination_name, base_duration_minutes, polyline_coords)
SELECT id, 'outbound', 'Maharagama', 'Pettah', 75,
    '[[79.9282,6.8469],[79.9100,6.8600],[79.8900,6.8800],[79.8700,6.9000],[79.8503,6.9369]]'::jsonb
FROM routes WHERE route_number = '138'
AND NOT EXISTS (SELECT 1 FROM route_variants rv JOIN routes r ON rv.route_id=r.id WHERE r.route_number='138' AND rv.direction='outbound');

INSERT INTO route_variants (route_id, direction, origin_name, destination_name, base_duration_minutes, polyline_coords)
SELECT id, 'inbound', 'Pettah', 'Maharagama', 75,
    '[[79.8503,6.9369],[79.8700,6.9000],[79.8900,6.8800],[79.9100,6.8600],[79.9282,6.8469]]'::jsonb
FROM routes WHERE route_number = '138'
AND NOT EXISTS (SELECT 1 FROM route_variants rv JOIN routes r ON rv.route_id=r.id WHERE r.route_number='138' AND rv.direction='inbound');

BEGIN;
    DROP PUBLICATION IF EXISTS supabase_realtime;
    CREATE PUBLICATION supabase_realtime FOR TABLE live_bus_positions;
COMMIT;

ALTER TABLE live_bus_positions REPLICA IDENTITY FULL;

CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT,
    role TEXT DEFAULT 'passenger',
    full_name TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Profiles public read"  ON profiles;
CREATE POLICY "Profiles public read"  ON profiles FOR SELECT USING (true);
DROP POLICY IF EXISTS "Profiles own insert"   ON profiles;
CREATE POLICY "Profiles own insert"   ON profiles FOR INSERT WITH CHECK (auth.uid() = id);
DROP POLICY IF EXISTS "Profiles own update"   ON profiles;
CREATE POLICY "Profiles own update"   ON profiles FOR UPDATE USING (auth.uid() = id);

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, email, role, full_name)
  VALUES (new.id, new.email, 'passenger',
          COALESCE(new.raw_user_meta_data->>'full_name', ''));
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

CREATE TABLE IF NOT EXISTS favourites (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    route_id UUID REFERENCES routes(id) ON DELETE CASCADE,
    label TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, route_id)
);

ALTER TABLE favourites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage favourites" ON favourites;
CREATE POLICY "Users manage favourites" ON favourites FOR ALL USING (auth.uid() = user_id);

CREATE OR REPLACE VIEW live_fresh_buses AS
SELECT * FROM live_bus_positions
WHERE last_updated_at >= NOW() - INTERVAL '15 minutes';

CREATE INDEX IF NOT EXISTS idx_live_bus_route       ON live_bus_positions(route_number);
CREATE INDEX IF NOT EXISTS idx_live_bus_last_updated ON live_bus_positions(last_updated_at);
CREATE INDEX IF NOT EXISTS idx_profiles_role         ON profiles(role);